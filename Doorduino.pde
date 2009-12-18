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

#if 0
#include <FatStructs.h>
#include <Fat16Config.h>
#include <Fat16mainpage.h>
#include <Fat16util.h>
#include <SdInfo.h>
#include <SdCard.h>
#include <Fat16.h>
#endif


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

time rtcTime;

// RFIDDB interface to handle ID lookup, logging function
RFIDDB rfiddb;

// Software serial device to talk to RFID reader
SoftwareSerial RFID =  SoftwareSerial(RFID_RX_PIN, RFID_TX_PIN);


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
}


// Build a human-readable representation of the current time
// @string  character array to put the time in, must be 20 bytes long
void getTime(char* string)
{
  // Grab the latest time from the RTC
  getClock();
  
  // And build a formatted string to represent it
  sprintf(string, "20%02d/%02d/%02d %02d:%02d:%02d",
                  rtcTime.year, rtcTime.month, rtcTime.day,
                  rtcTime.hour, rtcTime.minute, rtcTime.second);
}

  
void setup()
{
  Serial.begin(9600);      // Hardware RS232 for administrative access
  
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
//           t: Check the current time
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
  case 'r':
    // for debugging, reset the clock to 0's
    // TODO: Delete me
    Wire.beginTransmission(DS1307);
    Wire.send(dec2Bcd(R_SECS));
    Wire.send(dec2Bcd(0));
    Wire.send(dec2Bcd(0));
    Wire.send(dec2Bcd(0));
    Wire.send(dec2Bcd(0));
    Wire.send(dec2Bcd(0));
    Wire.send(dec2Bcd(0));
    Wire.send(dec2Bcd(0));
    Wire.endTransmission();
    
    break;
    
  default:
    Serial.println("? Command not understood.  Try U, L, T, t");
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

    if (bytesread == 10)
    {  // if 10 digit read is complete 
      getClock();
      allowed = rfiddb.validTag(code);
      logAccessAttempt(code, allowed);

      if(allowed) {
        openDoor();
      } 
      else {
        rejectTag();
      }
    }

    bytesread = 0; 
    delay(500);                       // wait for a bit
  }
}


// Log the tag access attempt
// @code       10-byte access code
// @allowed    True if the attempt succeeded, false otherwise
void logAccessAttempt(char* code, boolean allowed)
{
  
  if (allowed)
  {
    char message[] = "GRANTED_ACCESS code=xxxxxxxxxx";

    for (int i = 0; i < 10; i++) {
      message[i+20] = code[i];
    }
    
    log(message);
  }
  else
  {
    char message[] = "DENIED_ACCESS code=xxxxxxxxxx";

    for (int i = 0; i < 10; i++) {
      message[i+19] = code[i];
    }
    
    log(message);
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
  digitalWrite(RFID_DISABLE_PIN, HIGH);
  digitalWrite(DOOR_STRIKE_PIN, HIGH);

  delay(OPEN_TIME_SECS * 1000);

  digitalWrite(DOOR_STRIKE_PIN, LOW);
  digitalWrite(RFID_DISABLE_PIN, LOW);
}


void getClock()
{
  Wire.beginTransmission(DS1307);
  Wire.send(R_SECS);
  Wire.endTransmission();
  
  Wire.requestFrom(DS1307, 7);
  rtcTime.second = bcd2Dec(Wire.receive());
  rtcTime.minute = bcd2Dec(Wire.receive());
  rtcTime.hour   = bcd2Dec(Wire.receive());
  rtcTime.wkDay  = bcd2Dec(Wire.receive());
  rtcTime.day    = bcd2Dec(Wire.receive());
  rtcTime.month  = bcd2Dec(Wire.receive());
  rtcTime.year   = bcd2Dec(Wire.receive());
}


void setClock()
{
  Wire.beginTransmission(DS1307);
  Wire.send(dec2Bcd(R_SECS));
  Wire.send(dec2Bcd(rtcTime.second));
  Wire.send(dec2Bcd(rtcTime.minute));
  Wire.send(dec2Bcd(rtcTime.hour));
  Wire.send(dec2Bcd(rtcTime.wkDay));
  Wire.send(dec2Bcd(rtcTime.day));
  Wire.send(dec2Bcd(rtcTime.month));
  Wire.send(dec2Bcd(rtcTime.year));
  Wire.endTransmission();
}

void setTimeFromSerial()
{
  char temp = 0;

  // Wait for full time to be received
  for (int i = 0; i < 7; i++)
  {
    while (Serial.available() == 0) {
    }

    temp = Serial.read();

    switch (i) {
      case 0: rtcTime.year = temp;    break;
      case 1: rtcTime.month = temp;   break;
      case 2: rtcTime.day = temp;     break;
      case 3: rtcTime.wkDay = temp;   break;
      case 4: rtcTime.hour = temp;    break;
      case 5: rtcTime.minute = temp;  break;
      case 6: rtcTime.second = temp;  break;
    }

    i++;
  }
  
  setClock();
  
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

