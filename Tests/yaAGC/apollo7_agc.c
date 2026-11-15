// SPDX-License-Identifier: GPL-2.0-or-later
#include "agc_engine.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned dsky_updates;

// This CPU test supplies the same channel 7 feedback as ApolloGuidance.
// Record other DSKY output here without emulating spacecraft peripherals.
void ChannelOutput(agc_t *state, int channel, int value)
{
	if (channel == 7)
		state->InputChannel[7] = state->OutputChannel7 = value & 0160;
	if (channel == 010)
		++dsky_updates;
}

int ChannelInput(agc_t *state)
{
	(void)state;
	return 0;
}

void ChannelRoutine(agc_t *state) { (void)state; }
void RequestRadarData(agc_t *state) { (void)state; }
void ShiftToDeda(agc_t *state, int data) { (void)state; (void)data; }
void UnblockSocket(int descriptor) { (void)descriptor; }

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "Usage: %s path/to/Colossus237.bin\n", argv[0]);
		return EXIT_FAILURE;
	}

	agc_t *computer = calloc(1, sizeof(*computer));
	if (!computer)
		return EXIT_FAILURE;

	int result = agc_engine_init(computer, argv[1], NULL, 0);
	if (result != 0) {
		fprintf(stderr, "yaAGC initialization or ROM loading failed (%d)\n", result);
		free(computer);
		return EXIT_FAILURE;
	}

	for (unsigned step = 0; step < 100000; ++step)
		agc_engine(computer);

	printf("Colossus 237 executed %" PRIu64 " cycles and issued %u DSKY updates\n",
		computer->CycleCounter, dsky_updates);
	int passed = computer->CycleCounter == 100000 && dsky_updates != 0;
	free(computer);
	return passed ? EXIT_SUCCESS : EXIT_FAILURE;
}
