
# Copyright (c) 2014-2018, Dr Alex Meakins, Raysect Project
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

from raysect.core.math._vec3 cimport _Vec3
from raysect.core.math.vector cimport Vector3D
from raysect.core.math.affinematrix cimport AffineMatrix3D


cdef class Quaternion:

    cdef public double x, y, z, s

    cdef Quaternion neg(self)

    cdef Quaternion add(self, Quaternion q2)

    cdef Quaternion sub(self, Quaternion q2)

    cdef Quaternion mul(self, Quaternion q2)

    cdef Quaternion mul_scalar(self, double d)

    cpdef Quaternion conjugate(self)

    cpdef Quaternion inverse(self)

    cpdef double norm(self)

    cdef Quaternion div(self, Quaternion q2)

    cdef Quaternion div_scalar(self, double d)

    cpdef Quaternion normalise(self)

    cpdef bint is_unit(self, double tolerance=*)

    cdef Vector3D get_axis(self, double tolerance=*)

    cdef double get_angle(self)

    cpdef tuple to_euler_angles(self, str ordering=*)

    cpdef Quaternion copy(self)

    cpdef Vector3D transform_vector(self, _Vec3 vector)

    cpdef AffineMatrix3D to_matrix(self)


cpdef Quaternion rotation_delta(Vector3D omega, double delta_t)


cdef inline Quaternion new_quaternion(double x, double y, double z, double s):
    """
    Quaternion factory function.

    Creates a new Quaternion object with less overhead than the equivalent Python
    call. This function is callable from cython only.
    """

    cdef Quaternion q
    q = Quaternion.__new__(Quaternion)
    q.s = s
    q.x = x
    q.y = y
    q.z = z
    return q

