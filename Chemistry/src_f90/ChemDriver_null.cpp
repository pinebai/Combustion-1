// Null Chemistry

#include "ChemDriver.H"

namespace
{
    bool initialized = false;
    
    void ChemDriver_Finalize() { initialized = false; }
}

bool
ChemDriver::isNull()
{
    return true;
}

ChemDriver::ChemDriver (int use_vode_in, int max_points_in)
    : use_vode(use_vode_in),
      max_points(max_points_in)
{
    if (!initialized) 
    {
	initOnce();
	BoxLib::ExecOnFinalize(ChemDriver_Finalize);
	initialized = true;
    }
}

void 
ChemDriver::initOnce ()
{
    mSpeciesNames.clear();
    mSpeciesNames.resize(2);
    mSpeciesNames[0] = "X";
    mSpeciesNames[1] = "Y";

    mElementNames.clear();
    mElementNames.resize(2);
    mElementNames[0] = "X";
    mElementNames[1] = "Y";
}

ChemDriver::~ChemDriver ()
{
    ;
}

int
ChemDriver::index(const std::string speciesName) const
{
    return -1;
}
