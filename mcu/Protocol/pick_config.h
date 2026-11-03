#ifndef PICK_CONFIG_H
#define PICK_CONFIG_H
/* Original CH2..CH6 poses, with operator-requested CH1 opening/closing tuning.
 * Geometry/path clearance still requires real observation; PWM is not feedback.
 */
#define PICK_OPEN_US 1000u
#define PICK_CLOSE_US 1500u
#define PICK_HOME_US  {PICK_CLOSE_US,1382,2157,1098,2191,1683}
#define PICK_LEFT_US  {PICK_CLOSE_US,1382,2157,1598,1270,2456}
#define PICK_RIGHT_US {PICK_CLOSE_US,1382,2157,1598,1270,1005}
#define PICK_SPLIT_X_CM 15.0f
#define PICK_GRIP_MOVE_MS 400u
#define PICK_GRIP_SETTLE_MS 250u
#define PICK_POSE_SETTLE_MS 60u
#define PICK_HEAVY_SETTLE_MS 100u /* CH5 and separate base turns retain settling. */
/* Bits: CH5=16; CH2/3/4/6=46. CH1 is always commanded separately. */
#endif
