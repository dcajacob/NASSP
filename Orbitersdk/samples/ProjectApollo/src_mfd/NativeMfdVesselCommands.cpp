// SPDX-License-Identifier: GPL-2.0-or-later
#include "NativeMfdVesselCommands.h"
#include "NasspOrbiterSdk.h"
#include "soundlib.h"
#include "saturn.h"
#include "LEM.h"

// Dispatch through modules that own these subsystem objects. The MFD sees
// their declarations and can otherwise turn embedded-object calls into
// references to implementations that are private to the vessel modules.
namespace nassp::mfd {
void PressSwitch(PanelSwitchItem& control)
{
    control.SetState(true);
}

void SetRandomFailures(CSMMalfunctionSimulation& failures, double multiplier)
{
    failures.SetRandomFailures(multiplier);
}

void SetO2Hose(CSMToLEMECSConnector& connector, bool connected)
{
    if (connected) connector.ConnectCSMO2Hose();
    else connector.DisconnectCSMO2Hose();
}

void JettisonEquipment(LEMForwardHatch& hatch)
{
    hatch.JettisonEquipment();
}
}
