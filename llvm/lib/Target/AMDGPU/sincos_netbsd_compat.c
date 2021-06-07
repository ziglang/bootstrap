#include <math.h>

void sincos(double x, double *sin_result, double *cos_result) {
	*sin_result = sin(x);
	*cos_result = cos(x);
}

void sincosf(float x, float *sin_result, float *cos_result) {
	*sin_result = sinf(x);
	*cos_result = cosf(x);
}

void sincosl(long double x, long double *sin_result, long double *cos_result) {
	*sin_result = sinl(x);
	*cos_result = cosl(x);
}
