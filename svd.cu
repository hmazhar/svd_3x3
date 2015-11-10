#include "defines.h"
#include "real2.h"
#include "real3.h"
#include "real4.h"
#include "matrix.h"

// Code based on code from PhysBam
// Oliver K. Smith. 1961. Eigenvalues of a symmetric 3 × 3 matrix. Commun. ACM 4, 4 (April 1961), 168-. DOI=http://dx.doi.org/10.1145/355578.366316

__host__ __device__ real3 Fast_Eigenvalues(const SymMat33& A)  // 24 mults, 20 adds, 1 atan2, 1 sincos, 2 sqrts
{
    real m = 1.0f / 3.0f * (A.x11 + A.x22 + A.x33);
    real a11 = A.x11 - m;
    real a22 = A.x22 - m;
    real a33 = A.x33 - m;
    real a12_sqr = A.x21 * A.x21;
    real a13_sqr = A.x31 * A.x31;
    real a23_sqr = A.x32 * A.x32;
    real p = 1.0f / 6.0f * (a11 * a11 + a22 * a22 + a33 * a33 + 2 * (a12_sqr + a13_sqr + a23_sqr));
    real q = 0.5f * (a11 * (a22 * a33 - a23_sqr) - a22 * a13_sqr - a33 * a12_sqr) + A.x21 * A.x31 * A.x32;
    real sqrt_p = Sqrt(p);
    real disc = p * p * p - q * q;
    real phi = 1.0f / 3.0f * ATan2(Sqrt(Max(0.0f, disc)), q);
    real c = Cos(phi);
    real s = Sin(phi);
    real sqrt_p_cos = sqrt_p * c;
    real root_three_sqrt_p_sin = Sqrt(3.0f) * sqrt_p * s;
    real3 lambda(m + 2.0f * sqrt_p_cos, m - sqrt_p_cos - root_three_sqrt_p_sin, m - sqrt_p_cos + root_three_sqrt_p_sin);
    Sort(lambda.z, lambda.y, lambda.x);
    return lambda;
}

__host__ __device__ Mat33 Fast_Eigenvectors(const SymMat33& A, real3& lambda) {
    // flip if necessary so that first eigenvalue is the most different
    bool flipped = false;
    real3 lambda_flip(lambda);
    if (lambda.x - lambda.y < lambda.y - lambda.z) {
        Swap(lambda_flip.x, lambda_flip.z);
        flipped = true;
    }

    // get first eigenvector
    real3 v1 = Largest_Column_Normalized(Cofactor_Matrix(A - lambda_flip.x));
    // form basis for orthogonal complement to v1, and reduce A to this space
    real3 v1_orthogonal = UnitOrthogonalVector(v1);
    Mat32 other_v(v1_orthogonal, Cross(v1, v1_orthogonal));
    SymMat22 A_reduced = Conjugate_With_Transpose(other_v, A);

    // find third eigenvector from A_reduced, and fill in second via cross product
    real3 v3 = other_v * Largest_Column_Normalized(Cofactor_Matrix(A_reduced - lambda_flip.z));

    real3 v2 = Cross(v3, v1);

    return flipped ? Mat33(v3, v2, -v1) : Mat33(v1, v2, v3);
}

__host__ __device__ void Fast_Solve_EigenProblem(const SymMat33& A, real3& eigen_values, Mat33& eigen_vectors) {
    eigen_values = Fast_Eigenvalues(A);
    eigen_vectors = Fast_Eigenvectors(A, eigen_values);
}

__host__ __device__ void SVD(const Mat33& A, Mat33& U, real3& singular_values, Mat33& V) {
    SymMat33 ATA = NormalEquationsMatrix(A);
    real3 lambda;
    Fast_Solve_EigenProblem(ATA, lambda, V);

    if (lambda.z < 0) {
        lambda = ClampMin(lambda, 0.0f);
    }
    singular_values = Sqrt(lambda);  // 3s
    if (Determinant(A) < 0) {
        singular_values.z = -singular_values.z;
    }

    // compute singular vectors
    U.cols[0] = Normalize(A * V.cols[0]);
    real3 v1 = UnitOrthogonalVector(U.cols[0]);
    real3 v2 = Cross(U.cols[0], v1);

    real3 v3 = A * V.cols[1];
    real2 other_v = Normalize(real2(Dot(v1, v3), Dot(v2, v3)));
    U.cols[1] = real3(v1.x * other_v.x + v2.x * other_v.y, v1.y * other_v.x + v2.y * other_v.y, v1.z * other_v.x + v2.z * other_v.y);
    U.cols[2] = Cross(U.cols[0], U.cols[1]);
}
