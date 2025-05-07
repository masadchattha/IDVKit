/* opj_config_private.h — handwritten for VerifID's SPM build (Apple platforms).
   Values match a CMake-generated config for OpenJPEG 2.5.4 on Darwin. */
#ifndef OPJ_CONFIG_PRIVATE_H_INCLUDED
#define OPJ_CONFIG_PRIVATE_H_INCLUDED

#define OPJ_PACKAGE_VERSION "2.5.4"

#define OPJ_HAVE_FSEEKO
#define OPJ_HAVE_POSIX_MEMALIGN

#if !defined(_POSIX_C_SOURCE)
#if defined(OPJ_HAVE_FSEEKO) || defined(OPJ_HAVE_POSIX_MEMALIGN)
#define _POSIX_C_SOURCE 200112L
#endif
#endif

/* Apple platforms: endianness from the compiler. */
#if defined(__BIG_ENDIAN__)
#define OPJ_BIG_ENDIAN
#endif

#endif
