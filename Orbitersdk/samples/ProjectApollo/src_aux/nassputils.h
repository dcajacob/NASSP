/***************************************************************************
  This file is part of Project Apollo - NASSP

  NASSP utility functions

  Project Apollo is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  Project Apollo is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Project Apollo; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

  See http://nassp.sourceforge.net/license/ for more details.

  **************************************************************************/

#pragma once

#include "NasspOrbiterSdk.h"

#define NUM_ELEMENTS(x) (sizeof((x))/sizeof((x)[0]))

#if defined(_OPENORBITER) || defined(NASSP_NATIVE_LINUX)
#define MAT_EMISSION MatProp::Emission
#define MAT_LIGHT MatProp::Light
#else
#define MAT_EMISSION MESHM_EMISSION2
#define MAT_LIGHT MESHM_EMISSION
#endif


namespace nassp
{
	namespace utils
	{
		enum ClassNames
		{
			SaturnIB,
			SaturnV,
			Saturn,
			LEM,
			MCC,
			Skylab,
			SaturnIB_SIVB,
			SaturnV_SIVB,
			SIVB,
			ML,
			Crawler,
			MainChute,
			DrogueChute
		};

		static inline bool IsVessel(VESSEL *v, ClassNames name)
		{
			const char *classname = v->GetClassName();
			switch (name)
			{
			case SaturnIB:
				if (!stricmp(classname, "ProjectApollo\\Saturn1b") || !stricmp(classname, "ProjectApollo/Saturn1b")) return true;
				return false;
			case SaturnV:
				if (!stricmp(classname, "ProjectApollo\\Saturn5") || !stricmp(classname, "ProjectApollo/Saturn5")) return true;
				return false;
			case LEM:
				if (!stricmp(classname, "ProjectApollo\\LEM") || !stricmp(classname, "ProjectApollo/LEM")) return true;
				return false;
			case MCC:
				if (!stricmp(classname, "ProjectApollo\\MCC") || !stricmp(classname, "ProjectApollo/MCC")) return true;
				return false;
			case Skylab:
				if (!stricmp(classname, "ProjectApollo\\Skylab") || !stricmp(classname, "ProjectApollo/Skylab")) return true;
				return false;
			case SaturnIB_SIVB:
				if (!stricmp(classname, "ProjectApollo\\nsat1stg2") || !stricmp(classname, "ProjectApollo/nsat1stg2")) return true;
				return false;
			case SaturnV_SIVB:
				if (!stricmp(classname, "ProjectApollo\\sat5stg3") || !stricmp(classname, "ProjectApollo/sat5stg3")) return true;
				return false;
			case ML:
				if (!stricmp(classname, "ProjectApollo\\ML") || !stricmp(classname, "ProjectApollo/ML")) return true;
				return false;
			case Crawler:
				if (!stricmp(classname, "ProjectApollo\\Crawler") || !stricmp(classname, "ProjectApollo/Crawler")) return true;
				return false;
			case MainChute:
				if (!stricmp(classname, "ProjectApollo\\MainChute") || !stricmp(classname, "ProjectApollo/MainChute")) return true;
				return false;
			case DrogueChute:
				if (!stricmp(classname, "ProjectApollo\\DrogueChute") || !stricmp(classname, "ProjectApollo/DrogueChute")) return true;
				return false;
			case Saturn:
				return (IsVessel(v, SaturnIB) || IsVessel(v, SaturnV));
			case SIVB:
				return (IsVessel(v, SaturnIB_SIVB) || IsVessel(v, SaturnV_SIVB));
			}
			return false;
		}
	}
}
