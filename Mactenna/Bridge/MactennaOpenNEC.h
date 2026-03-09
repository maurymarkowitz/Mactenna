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

// ---------------------------------------------------------------------------
// Deck access helpers — used by Swift when deck_t is treated as opaque
// ---------------------------------------------------------------------------

/// Return pointer to first card in the deck (may be NULL).
static inline card_t *deck_cards(deck_t *d)
{
    return d ? d->cards : NULL;
}

/// Number of cards in the deck (0 if deck is NULL).
static inline int deck_num_cards(deck_t *d)
{
    return d ? d->num_cards : 0;
}

/// Safe card pointer by index; returns NULL if out-of-bounds or deck null.
static inline card_t *deck_card_at(deck_t *d, int idx)
{
    if (!d || idx < 0 || idx >= d->num_cards)
        return NULL;
    return &d->cards[idx];
}

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

// declaration for time estimation helper (added per user request)
// The real definition lives in misc.c; we only need a prototype here.
extern double nec_estimate_time(nec_context_t *ctx, deck_t *deck);

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

// ---------------------------------------------------------------------------
// Full-sphere pattern computation helper
//
// Configures ctx->fpat for a complete sphere at `step_deg` angular resolution,
// then calls compute_radiation_pattern() reusing the geometry and currents
// that were solved by the most recent nec_run_simulation() call.
//
// The geometry coordinate arrays are temporarily scaled from metres to
// wavelengths (exactly as execute_extra_patterns does) and restored
// afterwards, leaving the context ready for further calls.
//
// Prerequisites:
//   ctx->frequency_loop_ran  — true (currents solved)
//   ctx->geometry.num_segs   — > 0  (geometry computed)
//
// Returns  0 on success
//         -1 if ctx is NULL or step_deg <= 0
//         -2 if geometry not computed  (num_segs == 0 && num_patches == 0)
//         -3 if currents not solved    (frequency_loop_ran == false)
// ---------------------------------------------------------------------------
static inline int nec_compute_full_pattern(nec_context_t *ctx, double step_deg)
{
    if (!ctx || step_deg <= 0.0)
        return -1;
    if (ctx->geometry.num_segs == 0 && ctx->geometry.num_patches == 0)
        return -2;
    if (!ctx->frequency_loop_ran)
        return -3;

    /* Full sphere: theta 0–180° inclusive, phi 0–<360° */
    int n_theta = (int)(180.0 / step_deg) + 1;
    int n_phi = (int)(360.0 / step_deg);
    if (n_theta < 2)
        n_theta = 2;
    if (n_phi < 1)
        n_phi = 1;

    /* Configure fpat.
     * excitation_type is intentionally preserved — it was set by the EX
     * card during the original simulation run and must not be overwritten. */
    ctx->fpat.num_theta = n_theta;
    ctx->fpat.num_phi = n_phi;
    ctx->fpat.theta_start = 0.0;
    ctx->fpat.phi_start = 0.0;
    ctx->fpat.theta_step = step_deg;
    ctx->fpat.phi_step = step_deg;
    ctx->fpat.range = 0.0;
    ctx->fpat.norm_gain = 0.0;
    ctx->fpat.gain_type = 0; /* power gain (dBi) */
    ctx->fpat.avg_power_flag = (n_theta >= 2 && n_phi >= 2) ? 1 : 0;
    ctx->fpat.normalize_gain = 0;
    ctx->fpat.pol_axis = 0;
    ctx->fpat.is_near_field = -1; /* far-field only */

    /* Copy input power / network loss so compute_radiation_pattern can
     * correctly compute radiated power and efficiency. */
    ctx->fpat.power_in = ctx->netcx.power_in;
    ctx->fpat.network_loss = ctx->netcx.power_net_loss;

    /* Override far_field_type to 0 (normal far-field) — this is the gate
     * used by execute_extra_patterns before calling compute_radiation_pattern.
     * Save and restore so repeated calls see a consistent context. */
    int saved_far_field_type = ctx->gnd.far_field_type;
    ctx->gnd.far_field_type = 0;

    /* Scale geometry from metres to wavelengths */
    double fr = ctx->save.freq_mhz / CVEL;
    for (int i = 0; i < ctx->geometry.num_segs; i++)
    {
        ctx->geometry.x_center[i] *= fr;
        ctx->geometry.y_center[i] *= fr;
        ctx->geometry.z_center[i] *= fr;
        ctx->geometry.half_len[i] *= fr;
        ctx->geometry.radius[i] *= fr;
    }
    if (ctx->geometry.num_patches > 0)
    {
        double fr2 = fr * fr;
        for (int i = 0; i < ctx->geometry.num_patches; i++)
        {
            ctx->geometry.patch_x_center[i] *= fr;
            ctx->geometry.patch_y_center[i] *= fr;
            ctx->geometry.patch_z_center[i] *= fr;
            ctx->geometry.patch_area[i] *= fr2;
        }
    }

    compute_radiation_pattern(ctx);

    /* Restore geometry to unscaled (metre) values */
    for (int i = 0; i < ctx->geometry.num_segs; i++)
    {
        ctx->geometry.x_center[i] /= fr;
        ctx->geometry.y_center[i] /= fr;
        ctx->geometry.z_center[i] /= fr;
        ctx->geometry.half_len[i] /= fr;
        ctx->geometry.radius[i] /= fr;
    }
    if (ctx->geometry.num_patches > 0)
    {
        double fr2 = fr * fr;
        for (int i = 0; i < ctx->geometry.num_patches; i++)
        {
            ctx->geometry.patch_x_center[i] /= fr;
            ctx->geometry.patch_y_center[i] /= fr;
            ctx->geometry.patch_z_center[i] /= fr;
            ctx->geometry.patch_area[i] /= fr2;
        }
    }

    ctx->gnd.far_field_type = saved_far_field_type;
    return 0;
}

#endif /* MactennaOpenNEC_h */
