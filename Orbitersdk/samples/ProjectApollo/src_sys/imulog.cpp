/***************************************************************************
  This file is part of Project Apollo - NASSP
  Copyright 2004-2005

  IMU code

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

// To force Orbitersdk.h to use <fstream> in any compiler version
#pragma include_alias( <fstream.h>, <fstream> )
#include "NasspOrbiterSdk.h"
#include <chrono>
#include <ctime>
#include <stdio.h>
#include <math.h>
#include "soundlib.h"

#include "nasspdefs.h"
#include "apolloguidance.h"
#include "dsky.h"

#include "ioChannels.h"
#include "IMU.h"

#ifdef _DEBUG
namespace {
FILE* logFile = nullptr;

unsigned GetLogTimestamp(char (&clock)[9])
{
	using namespace std::chrono;
	const auto now = system_clock::now();
	const auto seconds = floor<std::chrono::seconds>(now);
	const auto time = system_clock::to_time_t(seconds);
	std::tm local{};
#if defined(_WIN32)
	localtime_s(&local, &time);
#else
	localtime_r(&time, &local);
#endif
	std::strftime(clock, sizeof(clock), "%H:%M:%S", &local);
	return static_cast<unsigned>(duration_cast<milliseconds>(now - seconds).count());
}
}
#endif

char *intToBinaryString(char *buffer, int i);


void IMU::LogInit() 

{
#ifdef _DEBUG
	if (!logFile)
#ifdef SAT5_LMPKD_EXPORTS
		logFile = fopen("ProjectApollo LM IMU.log", "w");
#else
		logFile = fopen("ProjectApollo IMU.log", "w");
#endif
#endif
}

void IMU::LogState(int channel, char *device, int value) 

{
#ifdef _DEBUG
	if (!logFile) return;
	char buffer[9];
	const unsigned milliseconds = GetLogTimestamp(buffer);
	char buffer1[100];
	
	intToBinaryString(buffer1, value);

		fprintf(logFile, "%.8s.%03u Ch %03o %s %s PIPA %o %o %o CDUCMD %o %o %o GYRO %o IMU %.2f %.2f %.2f\n", buffer, milliseconds, channel, device, buffer1,
		    agc.GetErasable(0, RegPIPAX), 
		    agc.GetErasable(0, RegPIPAY), 
			agc.GetErasable(0, RegPIPAZ), 
			agc.GetErasable(0, RegCDUXCMD),
			agc.GetErasable(0, RegCDUYCMD),
			agc.GetErasable(0, RegCDUZCMD),
			//state->Erasable[0][RegCDUX],
			//state->Erasable[0][RegCDUY],
			//state->Erasable[0][RegCDUZ],			
			agc.GetErasable(0, RegGYROCTR),
			radToDeg(Gimbal.X),
			radToDeg(Gimbal.Y),
			radToDeg(Gimbal.Z));
			
	fflush(logFile);
#endif
}

void IMU::LogTimeStep(long simt) 

{
#ifdef _DEBUG
	if (!logFile) return;
	char buffer[9];
	const unsigned milliseconds = GetLogTimestamp(buffer);
		
	fprintf(logFile, "%.8s.%03u TimeStep                   IMU %.2f %.2f %.2f\n", buffer, milliseconds,
			radToDeg(Gimbal.X),
			radToDeg(Gimbal.Y),
			radToDeg(Gimbal.Z));

	fflush(logFile);
#endif
}


void IMU::LogVector(char* message, VECTOR3 v) 

{
#ifdef _DEBUG
	if (!logFile) return;
	char buffer[9];
	const unsigned milliseconds = GetLogTimestamp(buffer);
		
	fprintf(logFile, "%.8s.%03u %s Vector %f %f %f\n", buffer, milliseconds,
			message, v.x, v.y, v.z);
#endif
}

void IMU::LogMessage(char* s) 

{
#ifdef _DEBUG
	if (!logFile) return;
	char buffer[9];
	const unsigned milliseconds = GetLogTimestamp(buffer);
		
	fprintf(logFile, "%.8s.%03u Message %s\n", buffer, milliseconds,
			s);	
#endif
}

char *intToBinaryString(char *buffer, int i) {

	unsigned int base = 0x4000; /* Assuming 15 bits */
	int pos = 0;

	while (base) {
		sprintf(&(buffer[pos]), "%c", (base & i) ? '1' : '0');
		base = base >> 1;
		pos++;
	}
	return(buffer);
}
