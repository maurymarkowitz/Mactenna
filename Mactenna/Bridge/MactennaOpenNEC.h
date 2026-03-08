//
//  MactennaOpenNEC.h
//  Mactenna
//
//  Objective‑C bridging header used by Swift code to see the OpenNEC C API.
//
//  Point your target's Swift Compiler > Objective‑C Bridging Header at this
//  file.  OpenNEC headers are pulled in via the Xcode configuration file
//  `OpenNEC.xcconfig` (HEADER_SEARCH_PATHS points at $(OPENNEC_ROOT)/src).

#ifndef MactennaOpenNEC_h
#define MactennaOpenNEC_h

#include "opennec.h"
// The public headers already declare the deck manipulation helpers that
// we call from Swift (insert_card, remove_card, move_card, append_card_from_text,
// card_is_toggleable, card_disable, card_enable, etc.).  No extra `extern`
// prototypes are necessary here – they come through opennec.h.

// Including internals.h exposes the full definition of nec_context_t so that
// Swift can treat `UnsafeMutablePointer<nec_context_t>` as a typed pointer and
// access fields directly in inline helpers below.
#include "internals.h"

// ── Simulation result accessors ──────────────────────────────────────────────
// Swift uses these small inline helpers to read data from the context without
// having to marshal large structs or call output routines.
// All indexes are zero‑based.

static inline bool nec_result_xt_terminated(const nec_context_t *ctx)
{
    return ctx->xt_terminated;
}

static inline double nec_result_freq_mhz(const nec_context_t *ctx)
{
    return ctx->save.freq_mhz; // renamed field in run_params_t
}

// antenna input / network data
static inline int nec_result_ninp(const nec_context_t *ctx)
{
    return ctx->netcx.ninp;
}
static inline int nec_result_inp_tag(const nec_context_t *ctx, int i)
{
    return ctx->netcx.inp_tag ? ctx->netcx.inp_tag[i] : 0;
}
static inline int nec_result_inp_seg(const nec_context_t *ctx, int i)
{
    return ctx->netcx.inp_seg ? ctx->netcx.inp_seg[i] : 0;
}
static inline double nec_result_inp_z_r(const nec_context_t *ctx, int i)
{
    return ctx->netcx.inp_z ? creal(ctx->netcx.inp_z[i]) : 0.0;
}
static inline double nec_result_inp_z_i(const nec_context_t *ctx, int i)
{
    return ctx->netcx.inp_z ? cimag(ctx->netcx.inp_z[i]) : 0.0;
}
static inline double nec_result_inp_y_r(const nec_context_t *ctx, int i)
{
    return ctx->netcx.inp_y ? creal(ctx->netcx.inp_y[i]) : 0.0;
}
static inline double nec_result_inp_y_i(const nec_context_t *ctx, int i)
{
    return ctx->netcx.inp_y ? cimag(ctx->netcx.inp_y[i]) : 0.0;
}
static inline double nec_result_inp_pwr(const nec_context_t *ctx, int i)
{
    return ctx->netcx.inp_pwr ? ctx->netcx.inp_pwr[i] : 0.0;
}
static inline double nec_result_pin(const nec_context_t *ctx)
{
    // field was renamed in network_context_t; now called power_in
    return ctx->netcx.power_in;
}

// How much power is lost in the network itself (PNLS)
static inline double nec_result_power_net_loss(const nec_context_t *ctx)
{
    return ctx->netcx.power_net_loss;
}

// radiation pattern summary
static inline int nec_result_rpat_npoints(const nec_context_t *ctx)
{
    return ctx->rpat.num_points;
}
static inline double nec_result_rpat_gmax(const nec_context_t *ctx)
{
    return ctx->rpat.gmax;
}
static inline double nec_result_rpat_pint(const nec_context_t *ctx)
{
    return ctx->rpat.pint;
}
static inline double nec_result_rpat_theta(const nec_context_t *ctx, int i)
{
    return ctx->rpat.points ? ctx->rpat.points[i].theta : 0.0;
}
static inline double nec_result_rpat_phi(const nec_context_t *ctx, int i)
{
    return ctx->rpat.points ? ctx->rpat.points[i].phi : 0.0;
}
static inline double nec_result_rpat_gtot(const nec_context_t *ctx, int i)
{
    return ctx->rpat.points ? ctx->rpat.points[i].gtot : 0.0;
}
static inline double nec_result_rpat_gnh(const nec_context_t *ctx, int i)
{
    return ctx->rpat.points ? ctx->rpat.points[i].gnh : 0.0;
}
static inline double nec_result_rpat_gnv(const nec_context_t *ctx, int i)
{
    return ctx->rpat.points ? ctx->rpat.points[i].gnv : 0.0;
}
static inline double nec_result_rpat_gnmj(const nec_context_t *ctx, int i)
{
    return ctx->rpat.points ? ctx->rpat.points[i].gnmj : 0.0;
}

// NGF-related state (new in 1.1.x)
static inline bool nec_result_has_ngf(const nec_context_t *ctx)
{
    return ctx->has_ngf;
}
static inline int nec_result_ngf_n_segs(const nec_context_t *ctx)
{
    return ctx->ngf_n_segs;
}
static inline int nec_result_ngf_neq(const nec_context_t *ctx)
{
    return ctx->ngf_neq;
}
static inline double nec_result_ngf_fmhz(const nec_context_t *ctx)
{
    return ctx->ngf_fmhz;
}

// informational messages and errors
static inline int nec_result_num_messages(const nec_context_t *ctx)
{
    return ctx->outputs.num_messages;
}
static inline const char *nec_result_message(const nec_context_t *ctx, int i)
{
    return ctx->outputs.messages ? ctx->outputs.messages[i] : NULL;
}
static inline int nec_result_num_errors(const nec_context_t *ctx)
{
    return ctx->errors.num_errors;
}
static inline const char *nec_result_error_msg(const nec_context_t *ctx, int i)
{
    return (ctx->errors.errors && ctx->errors.errors[i].message) ? ctx->errors.errors[i].message : NULL;
}

#endif /* MactennaOpenNEC_h */
