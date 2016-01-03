# cython: language_level=3

# Copyright (c) 2014-2015, Dr Alex Meakins, Raysect Project
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

import numpy as np
cimport numpy as np
from raysect.core.boundingbox cimport BoundingBox2D, new_boundingbox2d
from raysect.core.math.function.function2d cimport Function2D
from raysect.core.math.point cimport Point2D, new_point2d
from raysect.core.math.spatial.kdtree2d cimport KDTree2DCore, Item2D
cimport cython

# bounding box is padded by a small amount to avoid numerical accuracy issues
DEF BOX_PADDING = 1e-6

# convenience defines
DEF V1 = 0
DEF V2 = 1
DEF V3 = 2

DEF X = 0
DEF Y = 1


# todo: add docstrings
cdef class MeshKDTree(KDTree2DCore):

    def __init__(self, object vertices not None, object triangles not None):

        self._vertices = vertices
        self._triangles = triangles

        # check dimensions are correct
        if vertices.ndim != 2 or vertices.shape[1] != 2:
            raise ValueError("The vertex array must have dimensions Nx2.")

        if triangles.ndim != 2 or triangles.shape[1] != 3:
            raise ValueError("The triangle array must have dimensions Mx3.")

        # check triangles contains only valid indices
        invalid = (triangles[:, 0:3] < 0) | (triangles[:, 0:3] >= vertices.shape[0])
        if invalid.any():
            raise ValueError("The triangle array references non-existent vertices.")

        # kd-Tree init
        items = []
        for triangle in range(self._triangles.shape[0]):
            items.append(Item2D(triangle, self._generate_bounding_box(triangle)))
        super().__init__(items, max_depth=0, min_items=1, hit_cost=50.0, empty_bonus=0.2)

        # todo: check if triangles are overlapping?
        # (any non-owned vertex lying inside another triangle)

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef inline BoundingBox2D _generate_bounding_box(self, np.int32_t triangle):
        """
        Generates a bounding box for the specified triangle.

        A small degree of padding is added to the bounding box to provide the
        conservative bounds required by the watertight mesh algorithm.

        :param triangle: Triangle array index.
        :return: A BoundingBox3D object.
        """

        cdef:
            double[:, ::1] vertices
            np.int32_t[:, ::1] triangles
            np.int32_t i1, i2, i3
            BoundingBox2D bbox

        # assign locally to avoid repeated memory view validity checks
        vertices = self._vertices
        triangles = self._triangles

        i1 = triangles[triangle, V1]
        i2 = triangles[triangle, V2]
        i3 = triangles[triangle, V3]

        bbox = new_boundingbox2d(
            new_point2d(
                min(vertices[i1, X], vertices[i2, X], vertices[i3, X]),
                min(vertices[i1, Y], vertices[i2, Y], vertices[i3, Y]),
            ),
            new_point2d(
                max(vertices[i1, X], vertices[i2, X], vertices[i3, X]),
                max(vertices[i1, Y], vertices[i2, Y], vertices[i3, Y]),
            ),
        )
        bbox.pad(max(BOX_PADDING, bbox.largest_extent() * BOX_PADDING))

        return bbox

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef bint _hit_leaf(self, np.int32_t id, Point2D point):

        cdef:
            np.int32_t index, triangle, i1, i2, i3
            double alpha, beta, gamma

        # to avoid passing data via python objects (which is slow) we are
        # performing the interpolation inside this method and storing the
        # results in cython attributes

        # cache locally to avoid pointless memory view checks
        triangles = self._triangles

        # identify the first triangle that contains the point, if any
        for index in range(self._nodes[id].count):

            # obtain vertex indices
            triangle = self._nodes[id].items[index]
            i1 = triangles[triangle, V1]
            i2 = triangles[triangle, V2]
            i3 = triangles[triangle, V3]

            self._calc_barycentric_coords(i1, i2, i3, point.x, point.y, &alpha, &beta, &gamma)
            if self._hit_triangle(alpha, beta, gamma):

                # store vertex indices and barycentric coords
                self.i1 = i1
                self.i2 = i2
                self.i3 = i3
                self.alpha = alpha
                self.beta = beta
                self.gamma = gamma

                return True

        return False

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.cdivision(True)
    cdef inline void _calc_barycentric_coords(self, np.int32_t i1, np.int32_t i2, np.int32_t i3, double px, double py, double *alpha, double *beta, double *gamma):

        cdef:
            np.int32_t[:, ::1] triangles
            double[:, ::1] vertices
            double v1x, v2x, v3x, v1y, v2y, v3y
            double x1, x2, x3, y1, y2, y3
            double norm

        # cache locally to avoid pointless memory view checks
        vertices = self._vertices

        # obtain the vertex coords
        v1x = vertices[i1, X]
        v1y = vertices[i1, Y]

        v2x = vertices[i2, X]
        v2y = vertices[i2, Y]

        v3x = vertices[i3, X]
        v3y = vertices[i3, Y]

        # compute common values
        x1 = v1x - v3x
        x2 = v3x - v2x
        x3 = px - v3x

        y1 = v1y - v3y
        y2 = v2y - v3y
        y3 = py - v3y

        norm = 1 / (x1 * y2 + y1 * x2)

        # compute barycentric coordinates
        alpha[0] = norm * (x2 * y3 + y2 * x3)
        beta[0] = norm * (x1 * y3 - y1 * x3)
        gamma[0] = 1.0 - alpha[0] - beta[0]

    cdef inline bint _hit_triangle(self, double alpha, double beta, double gamma):

        # Point is inside triangle if all coordinates lie in range [0, 1]
        # if all are > 0 then none can be > 1 from definition of barycentric coordinates
        return alpha >= 0 and beta >= 0 and gamma >= 0


cdef class Interpolator2DMesh(Function2D):
    """
    An abstract data structure for interpolating data points lying on a triangular mesh.
    """

    def __init__(self, object vertex_coords not None, object vertex_data not None, object triangles not None, bint limit=True, double default_value=0.0):
        # """
        # :param ndarray vertex_coords: An array of vertex coordinates with shape (num of vertices, 2). For each vertex
        # there must be a (u, v) coordinate.
        # :param ndarray vertex_data: An array of data points at each vertex with shape (num of vertices).
        # :param ndarray triangles: An array of triangles with shape (num of triangles, 3). For each triangle, there must
        # be three indices that identify the three corresponding vertices in vertex_coords that make up this triangle.
        # """

        vertex_data = np.array(vertex_data, dtype=np.float64)
        vertex_coords = np.array(vertex_coords, dtype=np.float64)
        triangles = np.array(triangles, dtype=np.int32)

        # validate vertex_data
        if vertex_data.ndim != 1 or vertex_data.shape[0] != vertex_coords.shape[0]:
            raise ValueError("Vertex_data dimensions are incompatible with the number of vertices ({} vertices).".format(vertex_coords.shape[0]))

        # build kdtree
        self._kdtree = MeshKDTree(vertex_coords, triangles)

        self._vertex_data = vertex_data
        self._default_value = default_value
        self._limit = limit

    @classmethod
    def instance(cls, Interpolator2DMesh instance not None, object vertex_data=None, object limit=None, object default_value=None):

        cdef Interpolator2DMesh m

        # copy source data
        m = Interpolator2DMesh.__new__(Interpolator2DMesh)
        m._kdtree = instance._kdtree

        # do we have replacement vertex data?
        if vertex_data is None:
            m._vertex_data = instance._vertex_data
        else:
            m._vertex_data = np.array(vertex_data, dtype=np.float64)
            if m._vertex_data.ndim != 1 or m._vertex_data.shape[0] != instance._vertex_data.shape[0]:
                raise ValueError("Vertex_data dimensions are incompatible with the number of vertices in the instance ({} vertices).".format(instance._vertex_data.shape[0]))

        # do we have a replacement limit check setting?
        if limit is None:
            m._limit = instance._limit
        else:
            m._limit = limit

        # do we have a replacement default value?
        if default_value is None:
            m._default_value = instance._default_value
        else:
            m._default_value = default_value

        return m

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef double evaluate(self, double x, double y) except *:

        cdef:
            np.int32_t i1, i2, i3
            double alpha, beta, gamma

        if self._kdtree.hit(new_point2d(x, y)):

            # obtain hit data from kdtree attributes
            i1 = self._kdtree.i1
            i2 = self._kdtree.i2
            i3 = self._kdtree.i3
            alpha = self._kdtree.alpha
            beta = self._kdtree.beta
            gamma = self._kdtree.gamma

            return self._interpolate_triangle(i1, i2, i3, x, y, alpha, beta, gamma)

        if not self._limit:
            return self._default_value

        raise ValueError("Requested value outside mesh bounds.")

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef inline double _interpolate_triangle(self, np.int32_t i1, np.int32_t i2, np.int32_t i3, double px, double py, double alpha, double beta, double gamma):

        cdef:
            double[::1] vertex_data
            double v1, v2, v3

        # cache locally to avoid pointless memory view checks
        vertex_data = self._vertex_data

        # obtain the vertex data
        v1 = vertex_data[i1]
        v2 = vertex_data[i2]
        v3 = vertex_data[i3]

        # barycentric interpolation
        return alpha * v1 + beta * v2 + gamma * v3