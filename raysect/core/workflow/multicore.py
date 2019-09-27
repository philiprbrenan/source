# Copyright (c) 2014-2019, Dr Alex Meakins, Raysect Project
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     1. Redistributions of source code must retain the above copyright notice,
#        this list of conditions and the following disclaimer.
#
#     2. Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#
#     3. Neither the name of the Raysect Project nor the names of its
#        contributors may be used to endorse or promote products derived from
#        this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

from multiprocessing import Process, cpu_count, SimpleQueue
from ..math import random
from .base import RenderEngine


class MulticoreEngine(RenderEngine):
    """
    A render engine for distributing work across multiple CPU cores.

    The number of processes spawned by this render engine is controlled via
    the processes attribute. This can also be set at object initialisation.
   
    If the processes attribute is set to None (the default), the render engine
    will automatically set the number of processes to be equal to the number
    of CPU cores detected on the machine.

    If a render is being performed where the time to compute an individual task
    is comparable to the latency of the inter process communication (IPC), the
    render may run significantly slower than expected due to waiting for the
    IPC to complete. To reduce the impact of the IPC overhead, multiple tasks
    can be grouped together into jobs, requiring only one IPC wait for multiple
    tasks.

    By default a job consists of a single task. To increase the number of jobs
    per tasks, increase the value of the tasks_per_job attribute.

    :param processes: The number of worker processes, or None to use all available cores (default).
    :param tasks_per_job: The number of tasks to group into a single job (default=1)

    .. code-block:: pycon

        >>> from raysect.core import MulticoreEngine
        >>> from raysect.optical.observer import PinholeCamera
        >>>
        >>> camera = PinholeCamera((512, 512))
        >>>
        >>> # allowing the camera to use all available CPU cores.
        >>> camera.render_engine = MulticoreEngine()
        >>>
        >>> # or forcing the render engine to use a specific number of CPU processes
        >>> camera.render_engine = MulticoreEngine(processes=8)
    """

    def __init__(self, processes=None, tasks_per_job=None):
        super().__init__()
        self.processes = processes
        self.tasks_per_job = tasks_per_job or 1

    @property
    def processes(self):
        return self._processes

    @processes.setter
    def processes(self, value):
        if value is None:
            self._processes = cpu_count()
        else:
            value = int(value)
            if value <= 0:
                raise ValueError('Number of concurrent worker processes must be greater than zero.')
            self._processes = value

    @property
    def tasks_per_job(self):
        return self._tasks_per_job

    @tasks_per_job.setter
    def tasks_per_job(self, value):
        if value < 1:
            raise ValueError("The number of tasks per job must be greater than zero.")
        self._tasks_per_job = value

    def run(self, tasks, render, update, render_args=(), render_kwargs={}, update_args=(), update_kwargs={}):

        # establish ipc queues
        job_queue = SimpleQueue()
        result_queue = SimpleQueue()

        # start process to generate jobs
        producer = Process(target=self._producer, args=(tasks, job_queue))
        producer.start()

        # start worker processes
        workers = []
        for pid in range(self._processes):
            p = Process(target=self._worker, args=(render, render_args, render_kwargs, job_queue, result_queue))
            p.start()
            workers.append(p)

        # consume results
        remaining = len(tasks)
        while remaining:
            results = result_queue.get()
            for result in results:
                update(result, *update_args, **update_kwargs)
                remaining -= 1

        # shutdown workers
        for _ in workers:
            job_queue.put(None)

    def worker_count(self):
        return self._processes

    def _producer(self, tasks, job_queue):

        # break task list into jobs
        while tasks:
            job = []
            for _ in range(self._tasks_per_job):
                if tasks:
                    job.append(tasks.pop())
                    continue
                break
            job_queue.put(job)

    def _worker(self, render, args, kwargs, job_queue, result_queue):

        # re-seed the random number generator to prevent all workers inheriting the same sequence
        random.seed()

        # process jobs
        while True:

            job = job_queue.get()

            # have we been commanded to shutdown?
            if job is None:
                break

            results = []
            for task in job:
                results.append(render(task, *args, **kwargs))
            result_queue.put(results)
