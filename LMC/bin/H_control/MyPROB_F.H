#undef BL_LANG_CC
#ifndef BL_LANG_FORT
#define BL_LANG_FORT
#endif

#define SDIM BL_SPACEDIM

#include <REAL.H>
#include <CONSTANTS.H>
#include <BC_TYPES.H>
#include <PROB_AMR_F.H>
#include <PROB_F.H>
#include <ArrayLim.H>
#include <ChemDriver_F.H>
#include <HEATTRANSFER_F.H>
#if defined(BL_DO_FLCT)
#include <infl_frc.H>
#endif

#define BL_PROB_PREMIXED_FIXED_INFLOW 'premixed_fixed_inlet'
#define BL_PROB_PREMIXED_CONTROLLED_INFLOW 'premixed_controlled_inlet'
#define BL_PROB_PREMIXED_FREE 'premixed_free'
#define BL_PROB_DIFFUSION 'diffusion_two-stream'
#define BL_PROB_UNDEFINED 'undefined_problem'
#define BL_PROB_FUELBLOB 'fuelblob'


#define BL_XLO 0
#define BL_YLO 1
#define BL_XHI 2
#define BL_YHI 3
#define BL_ZLO 4
#define BL_ZHI 5
#define BL_INTERIOR 6

#define BL_FUELPIPE 1
#define BL_AMBIENT  2
#define BL_COFLOW   3
#define BL_STICK    4
#define BL_WALL     5
#define BL_VOLUME   6
#define BL_PIPEEND  7

