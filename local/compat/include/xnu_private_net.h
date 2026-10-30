/*
 * Networking constants from xnu's private headers, for tools built with the
 * public SDK (e.g. network_cmds' ping). These are kernel ABI values; they are
 * copied from Apple's open-source xnu, tag xnu-12377.121.6
 * (https://github.com/apple-oss-distributions/xnu/tree/xnu-12377.121.6):
 *
 *   SO_* socket options and traffic classes: bsd/sys/socket_private.h
 *   IP_NO_IFT_CELLULAR and _DSCP_* values:  bsd/netinet/in_private.h
 *
 * xnu is under the Apple Public Source License 2.0.
 *
 * ping force-includes this before any system header (-include), so these
 * definitions always apply; the #ifndef guards only avoid redefining a value.
 */

#ifndef APPLEUTILS_COMPAT_XNU_PRIVATE_NET_H
#define APPLEUTILS_COMPAT_XNU_PRIVATE_NET_H

#ifndef SO_TRAFFIC_CLASS
#define SO_TRAFFIC_CLASS	0x1086	/* Traffic service class (int) */
#endif
#ifndef SO_RECV_TRAFFIC_CLASS
#define SO_RECV_TRAFFIC_CLASS	0x1087	/* Receive traffic class (bool) */
#endif
#ifndef SO_RECV_ANYIF
#define SO_RECV_ANYIF		0x1104	/* unrestricted inbound processing */
#endif

#ifndef SO_TC_BK_SYS
#define SO_TC_BK_SYS	100	/* lowest class */
#endif
#ifndef SO_TC_BK
#define SO_TC_BK	200
#endif
#ifndef SO_TC_BE
#define SO_TC_BE	0
#endif
#ifndef SO_TC_RD
#define SO_TC_RD	300
#endif
#ifndef SO_TC_OAM
#define SO_TC_OAM	400
#endif
#ifndef SO_TC_AV
#define SO_TC_AV	500
#endif
#ifndef SO_TC_RV
#define SO_TC_RV	600
#endif
#ifndef SO_TC_VI
#define SO_TC_VI	700
#endif
#ifndef SO_TC_VO
#define SO_TC_VO	800
#endif
#ifndef SO_TC_CTL
#define SO_TC_CTL	900	/* highest class */
#endif

#ifndef IP_NO_IFT_CELLULAR
#define IP_NO_IFT_CELLULAR	6969
#endif

#ifndef _DSCP_DF
#define _DSCP_DF	0	/* RFC 2474 */
#define _DSCP_CS0	0	/* RFC 2474 */
#define _DSCP_CS1	8	/* RFC 2474 */
#define _DSCP_CS2	16	/* RFC 2474 */
#define _DSCP_CS3	24	/* RFC 2474 */
#define _DSCP_CS4	32	/* RFC 2474 */
#define _DSCP_CS5	40	/* RFC 2474 */
#define _DSCP_CS6	48	/* RFC 2474 */
#define _DSCP_CS7	56	/* RFC 2474 */
#define _DSCP_EF	46	/* RFC 2474 */
#define _DSCP_VA	44	/* RFC 5865 */
#define _DSCP_AF11	10	/* RFC 2597 */
#define _DSCP_AF12	12	/* RFC 2597 */
#define _DSCP_AF13	14	/* RFC 2597 */
#define _DSCP_AF21	18	/* RFC 2597 */
#define _DSCP_AF22	20	/* RFC 2597 */
#define _DSCP_AF23	22	/* RFC 2597 */
#define _DSCP_AF31	26	/* RFC 2597 */
#define _DSCP_AF32	28	/* RFC 2597 */
#define _DSCP_AF33	30	/* RFC 2597 */
#define _DSCP_AF41	34	/* RFC 2597 */
#define _DSCP_AF42	36	/* RFC 2597 */
#define _DSCP_AF43	38	/* RFC 2597 */
#endif

#endif /* APPLEUTILS_COMPAT_XNU_PRIVATE_NET_H */
