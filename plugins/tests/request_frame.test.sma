#include <amxmodx>
#include <fakemeta>
#include <amxxbench>

/*
Expected console output:

Command_Test - Frame: X
FrameCallback1 - Frame: X + 1 Data: 100
FrameCallback2 - Frame: X + 2 Data: 200
FrameCallback3 - Frame: X + 2 Data: 300
FrameCallback4 - Frame: X + 3 Data: 400
FrameCallback4 - Frame: X + 3 Data: 500

Port of plugins/testsuite/request_frame_test.sma: the test runs request_frame_test as a server
command, as the original was run, so that it executes between frames, and checks the frames and
data the callbacks record against the output above.
*/

#define CALLS 6

new g_frameNumber = 0;

new g_Calls;
new g_CallFrame[CALLS];
new g_CallData[CALLS];

new g_ExpectedFrame[CALLS] = {0, 1, 2, 2, 3, 3};
new g_ExpectedData[CALLS] = {0, 100, 200, 300, 400, 500};

public plugin_precache()
{
	register_forward(FM_StartFrame, "OnStartFrame", false);
}

public plugin_init()
{
	register_plugin("RequestFrame() Test", "1.0.0", "KliPPy");

	register_concmd("request_frame_test", "Command_Test");
}

public OnStartFrame()
{
	g_frameNumber++;
}

Record(data)
{
	if (g_Calls < CALLS)
	{
		g_CallFrame[g_Calls] = g_frameNumber;
		g_CallData[g_Calls] = data;
	}
	g_Calls++;
}

public Command_Test()
{
	console_print(0, "Command_Test - Frame: %d", g_frameNumber);
	Record(0);

	RequestFrame("FrameCallback1", 100);
}

public FrameCallback1(data)
{
	console_print(0, "FrameCallback1 - Frame: %d Data: %d", g_frameNumber, data);
	Record(data);

	RequestFrame("FrameCallback2", 200);
	RequestFrame("FrameCallback3", 300);
}

public FrameCallback2(data)
{
	console_print(0, "FrameCallback2 - Frame: %d Data: %d", g_frameNumber, data);
	Record(data);
	RequestFrame("FrameCallback4", 400);
}

public FrameCallback3(data)
{
	console_print(0, "FrameCallback3 - Frame: %d Data: %d", g_frameNumber, data);
	Record(data);
	RequestFrame("FrameCallback4", 500);
}

public FrameCallback4(data)
{
	console_print(0, "FrameCallback4 - Frame: %d Data: %d", g_frameNumber, data);
	Record(data);
}

public test_request_frame()
{
	g_Calls = 0;
	server_cmd("request_frame_test");
	bench_wait_until("AllCalled", "CheckCalls", 5.0);
}

public AllCalled(data)
{
	return g_Calls >= CALLS;
}

public CheckCalls(data)
{
	// one frame later, so that a seventh call would have been recorded
	bench_next("CheckCallsLater", 0.0);
}

public CheckCallsLater(data)
{
	ASSERT_EQ(g_Calls, CALLS);

	new X = g_CallFrame[0];
	for (new i = 1; i < CALLS; i++)
	{
		if (!bench_check(g_CallData[i] == g_ExpectedData[i], "callbacks run in the expected order with their data"))
			return;
		if (!bench_check(g_CallFrame[i] - X == g_ExpectedFrame[i], "callback runs on the expected frame"))
			return;
	}
	bench_pass();
}
