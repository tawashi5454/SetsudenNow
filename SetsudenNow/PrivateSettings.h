
// NOTE
// Before uploading to your Arduino board,
// please replace with your own settings



//****** REQUIRED to replace ******/

// (1) Mac address of your Ethernet Shield
byte macAddress[] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00};

// (2) The stweitter token
#define STEWITTER_TOKEN "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

// (3) Your Pachube API key (a public secure key is recommended)
#define PACHUBE_API_KEY "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

// (4) The Pachube environment ID of your feed
#define PACHUBE_ENVIRONMENT_ID 0



//****** OPTIONAL to replace ******/

// Update interval in minutes for Pachube
#define UPDATE_INTERVAL_IN_MINUTE 5

// Your usual daily electricity consumption(in Wh, Japanese average is about 10000 - 12000)
#define USUAL_CONSUMPTION 12000

// Time difference with UTC(In Japan, use 9)
#define TIME_ZONE_OFFSET 9

