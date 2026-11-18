// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

class CSMMalfunctionSimulation;
class CSMToLEMECSConnector;
class LEMForwardHatch;
class PanelSwitchItem;

namespace nassp::mfd {
#if defined(NASSP_NATIVE_LINUX)
void PressSwitch(PanelSwitchItem& control);
void SetRandomFailures(CSMMalfunctionSimulation& failures, double multiplier);
void SetO2Hose(CSMToLEMECSConnector& connector, bool connected);
void JettisonEquipment(LEMForwardHatch& hatch);
#else
inline void PressSwitch(PanelSwitchItem& control) { control.SetState(true); }
inline void SetRandomFailures(CSMMalfunctionSimulation& failures, double multiplier)
{
    failures.SetRandomFailures(multiplier);
}
inline void SetO2Hose(CSMToLEMECSConnector& connector, bool connected)
{
    if (connected) connector.ConnectCSMO2Hose();
    else connector.DisconnectCSMO2Hose();
}
inline void JettisonEquipment(LEMForwardHatch& hatch) { hatch.JettisonEquipment(); }
#endif
}
