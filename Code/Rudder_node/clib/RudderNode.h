#ifndef ECAN_RUDDER_H
#define ECAN_RUDDER_H

#include <stdint.h>

struct RudderCalibrationData {
	uint16_t PortLimitValue; // The lower limit on the rudder potentiometer.
	uint16_t StarLimitValue; // The upper limit on the rudder potentiometer.
	uint8_t CalibrationState;  // Tracks the internal state machine of the calibration FSM.
	uint8_t CommandedDirection; // Dictates the direction the rudder should be commanded.
	uint8_t CommandedRun; // Whether the rudder should be stepping now.
	bool RestoredCalibration; // If calibration data was restored after a reset.
	bool Calibrating;
	bool Calibrated;
};
extern struct RudderCalibrationData rudderCalData;

struct RudderSensorData {
	float CommandedRudderAngle; // The rudder angle in radians.
	float RudderPositionAngle; // The rudder angle in radians.
	float Temperature; // The temperature in Celsius.
	uint16_t PotValue; // The rudder potentiometer value.
	bool PortLimit; // Whether the port limit switch has been triggered.
	bool StarLimit; // Whether the starboard limit switch has been triggered.
};
extern struct RudderSensorData rudderSensorData;

/**
 * Initialize the rudder subsystem. Currently this means
 * scheduling repetitive transmission of CAN messages.
 */
void RudderSubsystemInit(void);

void RudderCalibrate(void);

/**
 * Transmit PGN 127245 (rudder angle) message via CAN.
 */
void RudderSendNmea(void);

/**
 * Transmit CUSTOM_LIMITS message via CAN.
 */
void RudderSendCustomLimit(void);

/**
 * Transmit PGN130311 (ambient temperature) message via CAN.
 */
void RudderSendTemperature(void);

/**
 * Manage the ECAN message system for a given timestamp. This
 * function reads in and processes all received timestamps. It
 * also checks which messages should be transmit for the current
 * timestep and sends those off.
 */
void SendAndReceiveEcan(void);

/**
 * Update the transmission rates of broadcast messages.
 * @param angleRate The desired transmission rate of the NMEA2000 PGN127245 message.
 * @param statusRate The desired transmission rate of the custom status message.
 */
void UpdateMessageRate(const uint8_t angleRate, const uint8_t statusRate);

/**
 * Helper function for retrieving whether a calibration should occur.
 * Used to pull this data into Simulink.
 * @returns A boolean for whether or not to calibrate.
 */
bool GetCalibrateMessage(void);

/**
 * Helper function for retrieving what the commanded angle should be.
 * Used to pull this data into Simulink.
 * @returns The desired angle in radians.
 */
float GetNewAngle(void);

/**
 * Convert the potentiometer readings to floating point radians. Tries to use integer math whenever
 * possible.
 */
float PotToRads(uint16_t input, uint16_t highSide, uint16_t lowSide);

#endif // ECAN_RUDDER_H
