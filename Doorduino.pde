// RFID Reader with RTC timestamping and door driving!
// Reports, via Serial, any RFID tags found along with timestamp and whether
// or not the tag was in the tag database.
// Also supports some commands over Serial:
//  - 'L' - Lists tags in the database, one per line
//  - 'U<#tags><tagdata>' - Accepts a new list of tags 
//                          (first byte # of tags, each tag is 10 chars
//  - [TODO] 'T<timedata>' - Set the clock YMDWhms
// Kludged together by Marty McGuire <http://creatingwithcode.com/>
// NOTE: Broken because SoftwareSerial doesn't support SS.available()!!!!

// DS1307 demo
// -- Found at http://www.arduino.cc/cgi-bin/yabb2/YaBB.pl?num=1198881858
// -- by Jon McPhalen (www.jonmcphalen.com) -- based on work by others
// -- 29 DEC 2007

// Parallax RFID demo
// Modified by Worapoht K.
// Found at http://www.arduino.cc/playground/Learning/PRFID
// RX uses Serial (Pin 0)
// /ENABLE on Digital2

#include <Wire.h>
#include <SoftwareSerial.h>

#include <EEPROM.h>        // TODO: Put this in RFIDDB library?

#include <RFIDDB.h>

#include <Fat16.h>
#include <Fat16util.h> // use functions to print strings from flash memory

SdCard card;
Fat16 file;

// Hardware Setup //////////////////////////////////////////////////////////////
#define RFID_DISABLE_PIN 2 // Digital pin connected to RFID reader /enable pin
#define RFID_RX_PIN 3      // Digital pin for software RFID read
#define RFID_TX_PIN 4      // Unusued

#define DOOR_STRIKE_PIN 5  // Digital pin connected to the door strike

#define OPEN_TIME_SECS 5   // Amount of time to open the door strike, in seconds

// DS1307 Clock chip definitions ///////////////////////////////////////////////
#define DS1307      0xD0 >> 1                   // shift required by Wire.h (silly...)

// DS1307 clock registers
#define R_SECS      0
#define R_MINS      1
#define R_HRS       2
#define R_WKDAY     3
#define R_DATE      4
#define R_MONTH     5
#define R_YEAR      6
#define R_SQW       7

// RTC reading vars
typedef struct time {
  byte second;
  byte minute;
  byte hour;
  byte wkDay;
  byte day;
  byte month;
  byte year;
};

// RFIDDB interface to handle ID lookup, logging function
RFIDDB rfiddb;

// Software serial device to talk to RFID reader
SoftwareSerial RFID =  SoftwareSerial(RFID_RX_PIN, RFID_TX_PIN);

// Hokey shit, destroy
// store error strings in flash to save RAM
#define error(s) error_P(PSTR(s))
void error_P(const char *str)
{
  PgmPrint("error: ");
  SerialPrintln_P(str);
  if (card.errorCode) {
    PgmPrint("SD error: ");
    Serial.println(card.errorCode, HEX);
  }
  while(1);
}


// Log a system message either to console or SD card
void log(char* message)
{ 
  static char timeString[20];
  getTime(timeString);
  
  // For now, just print it to the console
  Serial.print("[");
  Serial.print(timeString);
  Serial.print("] ");
  Serial.print(message);
  Serial.print("\n");
  
  file.print("[");
  file.print(timeString);
  file.print("] ");
  file.print(message);
  file.print("\n");
  
  if (!file.sync()) {
    Serial.print("Error logging to SD Card");
  }
}

  
void setup()
{
  Serial.begin(9600);      // Hardware RS232 for administrative access

  Serial.print("Starting");
  Serial.print("\n");


  // initialize the SD card
  if (!card.init()) error("card.init");
  
  // initialize a FAT16 volume
  if (!Fat16::init(card)) error("Fat16::init");
  
  // create a new file
  file.open("ACCESS.LOG", O_CREAT | O_APPEND | O_WRITE);
  if (!file.isOpen()) error ("create");

  Wire.begin();            // I2C bus for the clock chip
  
  pinMode(RFID_RX_PIN, INPUT);
  pinMode(RFID_TX_PIN, OUTPUT);
  RFID.begin(2400);        // Software RS232 for RFID reader

  // Initialize the door stop
  pinMode(DOOR_STRIKE_PIN, OUTPUT);
  digitalWrite(DOOR_STRIKE_PIN, LOW);  // Keep the door locked

  // And the RFID /enable pin
  pinMode(RFID_DISABLE_PIN, OUTPUT);
  digitalWrite(RFID_DISABLE_PIN, HIGH);   // Disable the RFID reader 

  // Set up the RFID card database
  rfiddb = RFIDDB();
    
  log("POWER_ON");
  
  int count = millis() + 5000;
  while (millis() < count) {
    if (Serial.available() > 0){
      char command = Serial.read();
      handleAdministrativeCommand(command);

      count = millis() + 5000;
    }
  }

  digitalWrite(RFID_DISABLE_PIN, LOW);   // Activate the RFID reader
  
  log("ACTIVATE_READER");
}

void loop()
{  
  readTag(); // blocks
}


// Handle the administrator command menu
// @command  U: Upload a new set of valid tags
//           L: List valid tags
//           T: Set the real time clock
void handleAdministrativeCommand(char command)
{
  char message[] = "GOT_COMMAND command=x";
  message[20] = command;
  log(message);
  
  switch(command){
  case 'U':
    Serial.println("Begin upload:");
    rfiddb.readTags();
    break;
  case 'L':
    rfiddb.printTags();
    break;
  case 'T':
    setTimeFromSerial();
    break;
  default:
//    Serial.println("? Command not understood.  Try U, L, T");
    Serial.println("?");
    break;
  }
}


// Read bytes from the RFID tag, and handle them appropriately
void readTag()
{
  int  val = 0;
  int  bytesread = 0;
  char code[10];

  boolean allowed = 0;

  val = RFID.read();

  // If a proper header was received, start reading RFID tag
  if (val == 10)
  {
    bytesread = 0; 
    while (bytesread < 10)
    {  // read 10 digit code 
      val = RFID.read(); 
      if((val == 10)||(val == 13))
      {  // if header or stop bytes before the 10 digit reading 
        break;                       // stop reading 
      } 
      code[bytesread] = val;         // add the digit           
      bytesread++;                   // ready to read next digit  
    } 

    // if 10 digit read is complete
    if (bytesread == 10)
    {
      allowed = rfiddb.validTag(code);

      char message[25+TAG_LENGTH];
      
      if(allowed) {
        sprintf(message, "GRANTED_ACCESS code=xxxxxxxxxx", code);
        strncpy(&message[20], code, TAG_LENGTH);
        log(message);

        openDoor();
      } 
      else {
        sprintf(message, "DENIED_ACCESS code=xxxxxxxxxx", code);
        strncpy(&message[19], code, TAG_LENGTH);
        log(message);
        
        rejectTag();
      }
    }

    bytesread = 0; 
    delay(500);                       // wait for a bit
  }
}


void rejectTag()
{
  // Flash the tag
  for(int i = 0; i < 3; i++){
    digitalWrite(RFID_DISABLE_PIN, HIGH);
    delay(500);
    digitalWrite(RFID_DISABLE_PIN, LOW);
    delay(500);  
  }

}


void openDoor()
{
  // Open the door
  digitalWrite(RFID_DISABLE_PIN, HIGH);
  digitalWrite(DOOR_STRIKE_PIN, HIGH);

  delay(OPEN_TIME_SECS * 1000);

  digitalWrite(DOOR_STRIKE_PIN, LOW);
  digitalWrite(RFID_DISABLE_PIN, LOW);
}


void readRTC(time& currentTime)
{
  Wire.beginTransmission(DS1307);
  Wire.send(R_SECS);
  Wire.endTransmission();
  
  Wire.requestFrom(DS1307, 7);
  currentTime.second = bcd2Dec(Wire.receive());
  currentTime.minute = bcd2Dec(Wire.receive());
  currentTime.hour   = bcd2Dec(Wire.receive());
  currentTime.wkDay  = bcd2Dec(Wire.receive());
  currentTime.day    = bcd2Dec(Wire.receive());
  currentTime.month  = bcd2Dec(Wire.receive());
  currentTime.year   = bcd2Dec(Wire.receive());
}


void setRTC(time& newTime)
{
  Wire.beginTransmission(DS1307);
  Wire.send(dec2Bcd(R_SECS));
  Wire.send(dec2Bcd(newTime.second));
  Wire.send(dec2Bcd(newTime.minute));
  Wire.send(dec2Bcd(newTime.hour));
  Wire.send(dec2Bcd(newTime.wkDay));
  Wire.send(dec2Bcd(newTime.day));
  Wire.send(dec2Bcd(newTime.month));
  Wire.send(dec2Bcd(newTime.year));
  Wire.endTransmission();
}


// Build a human-readable representation of the current time
// @string  character array to put the time in, must be 20 bytes long
void getTime(char* string)
{
  // Grab the latest time from the RTC
  time currentTime;
  readRTC(currentTime);
  
  // And build a formatted string to represent it
  sprintf(string, "20%02d/%02d/%02d %02d:%02d:%02d",
                  currentTime.year, currentTime.month, currentTime.day,
                  currentTime.hour, currentTime.minute, currentTime.second);
}


void setTimeFromSerial()
{
  time newTime;
  
  char temp = 0;

  // Wait for full time to be received
  for (int i = 0; i < 7; i++)
  {
    while (Serial.available() == 0) {}

    temp = Serial.read();

    switch (i) {
      case 0: newTime.year = temp;    break;
      case 1: newTime.month = temp;   break;
      case 2: newTime.day = temp;     break;
      case 3: newTime.wkDay = temp;   break;
      case 4: newTime.hour = temp;    break;
      case 5: newTime.minute = temp;  break;
      case 6: newTime.second = temp;  break;
    }
  }
  
  setRTC(newTime);
  
  log("TIME_RESET");
}


byte bcd2Dec(byte bcdVal)
{
  return bcdVal / 16 * 10 + bcdVal % 16;
}

byte dec2Bcd(byte decVal)
{
  return decVal / 10 * 16 + decVal % 10;
}

