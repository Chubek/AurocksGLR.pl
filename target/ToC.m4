include(`support.m4')
dnl The C backend is the reference backend: the Perl front-end emits a
dnl complete, portable C runtime as AUROCKS_C_SOURCE.
define([[AUROCKS_C_SOURCE]], [[$1]])
