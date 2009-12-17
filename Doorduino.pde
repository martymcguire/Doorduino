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
#include <NewSoftSerial.h>
#include <EEPROM.h>
#include <RFIDDB.h>

////////////////////////////////////////////////////////////////////////////////

// Hardware Setup //////////////////////////////////////////////////////////////
#define RFID_DISABLE_PIN 2 // Digital pin connected to RFID reader /enable pin
#define RFID_RX_PIN 3      // Digital pin for software RFID read

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
byte second = 0x00;                             // default to 01 JAN 2007, midnight
byte minute = 0x00;
byte   hour = 0x00;
byte  wkDay = 0x02;
byte    day = 0x01;
byte  month = 0x01;
byte   year = 0x07;
byte   ctrl = 0x00;


// RFIDDB interface to handle ID lookup, logging function
RFIDDB rfiddb;

// Software serial device to talk to RFID reader
NewSoftSerial RFID(RFID_RX_PIN, 255);


void setup()
{
  Wire.begin();            // I2C bus for the clock chip
  Serial.begin(9600);      // Hardware RS232 for administrative access
  RFID.begin(2400);        // Software RS232 for RFID reader

  Serial.flush();
  RFID.flush();

  Serial.println("Starting...");

  // Initialize the door stop
  pinMode(DOOR_STRIKE_PIN, OUTPUT);
  digitalWrite(DOOR_STRIKE_PIN, LOW);  // Keep the door locked

  // And the RFID /enable pin
  pinMode(RFID_DISABLE_PIN, OUTPUT);
  digitalWrite(RFID_DISABLE_PIN, HIGH);   // Disable the RFID reader 

  // Set up the RFID card database
  rfiddb = RFIDDB();


  digitalWrite(RFID_DISABLE_PIN, LOW);   // Activate the RFID reader 
  Serial.println("RFID reader activated");
}

void loop()
{ 
  if (Serial.available() > 0){
    char command = Serial.read();
    handleAdministrativeCommand(command);
  }
  if (RFID.available() > 0) {
    readTag(); // blocks
  }
}


// Handle the administrator command menu
// @command  U: Upload a new set of valid tags
//           L: List valid tags
//           T: Set the real time clock
void handleAdministrativeCommand(char command)
{ 
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
  }
}

// RFID reader vars
int  val = 0; 
char code[10]; 
int  bytesread = 0;

// Read bytes from the RFID tag, and handle them appropriately
void readTag()
{
  // If there isn't data waiting on the RFID pin, balk
  if (RFID.available() == 0) {
    return;
  }

  boolean allowed = 0;
  
  if((val = RFID.read()) == 10)
  {   // check for header 
    bytesread = 0; 
    while(bytesread<10)
    {  // read 10 digit code 
      while( RFID.available() == 0) {}
      val = RFID.read(); 
      if((val == 10)||(val == 13))
      {  // if header or stop bytes before the 10 digit reading 
        break;                       // stop reading 
      } 
      code[bytesread] = val;         // add the digit           
      bytesread++;                   // ready to read next digit  
    } 

    if(bytesread == 10)
    {  // if 10 digit read is complete 
      getClock();
      allowed = rfiddb.validTag(code);
      logTag(allowed);
      if(allowed) {
         openDoor();
      } else {
         rejectTag();
      }
    }
    bytesread = 0; 
    delay(500);                       // wait for a bit
  }
}

void logTag(boolean allowed)
{
  Serial.print("TAG code ");   // possibly a good TAG 
  for(int i = 0; i < 10; i++){ // print the TAG code
    Serial.print(code[i]);      
  }
  if(allowed){ Serial.print(" GRANTED"); }
  else {       Serial.print(" DENIED");  }
      
  Serial.print(" access at ");
  printTime();
  Serial.println();
}

void rejectTag()
{
  for(int i = 0; i < 3; i++){
    digitalWrite(RFID_DISABLE_PIN, HIGH);
    delay(500);
    digitalWrite(RFID_DISABLE_PIN, LOW);
    delay(500);  
  }
}

void openDoor()
{
//  digitalWrite(RFID_DISABLE_PIN, HIGH);
  digitalWrite(DOOR_STRIKE_PIN, HIGH);

  delay(OPEN_TIME_SECS * 1000);

  digitalWrite(DOOR_STRIKE_PIN, LOW);  
//  digitalWrite(RFID_DISABLE_PIN, LOW); 
}

void printTime()
{
  printHex2(hour);
  Serial.print(":");
  printHex2(minute);
  Serial.print(":");
  printHex2(second);
  Serial.print("  ");
  printDayName(bcd2Dec(wkDay));
  Serial.print("  ");
  printHex2(day);
  Serial.print(" ");
  printMonthName(bcd2Dec(month));
  Serial.print(" 20");
  printHex2(year);
}

void setClock()
{
  Wire.beginTransmission(DS1307);
  Wire.send(R_SECS);
  Wire.send(second);
  Wire.send(minute);
  Wire.send(hour);
  Wire.send(wkDay);
  Wire.send(day);
  Wire.send(month);
  Wire.send(year);
  Wire.send(ctrl);
  Wire.endTransmission();
}

void setTimeFromSerial()
{
  second = 255;
  minute = 255;
  hour   = 255;
  wkDay  = 255;
  day    = 255;
  month  = 255;
  year   = 255;
  boolean done = false;
  while(!done){
    if(Serial.available() > 0){
      if(year == 255){
        year = dec2Bcd(Serial.read());
      } else if (month == 255) {
        month = dec2Bcd(Serial.read());
      } else if (day == 255) {
        day = dec2Bcd(Serial.read());
      } else if (wkDay == 255) {
        wkDay = dec2Bcd(Serial.read() + 1);
      } else if (hour == 255) {
        hour = dec2Bcd(Serial.read());
      } else if (minute == 255) {
        minute = dec2Bcd(Serial.read());
      } else {
        second = dec2Bcd(Serial.read());
        done = true;
      }
    }
  }
  setClock();
  getClock();
  Serial.print("Time Set: ");
  printTime();
  Serial.println();
}

void getClock()
{
  Wire.beginTransmission(DS1307);
  Wire.send(R_SECS);
  Wire.endTransmission();
  Wire.requestFrom(DS1307, 8);
  second = Wire.receive();
  minute = Wire.receive();
  hour   = Wire.receive();
  wkDay  = Wire.receive();
  day    = Wire.receive();
  month  = Wire.receive();
  year   = Wire.receive();
  ctrl   = Wire.receive();
}


byte bcd2Dec(byte bcdVal)
{
  return bcdVal / 16 * 10 + bcdVal % 16;
}

byte dec2Bcd(byte decVal)
{
  return decVal / 10 * 16 + decVal % 10;
}


void printHex2(byte hexVal)
{
  if (hexVal < 0x10)
    Serial.print("0");
  Serial.print(hexVal, HEX);
}


void printDec2(byte decVal)
{
  if (decVal < 10)
    Serial.print("0");
  Serial.print(decVal, DEC);
}


char *dayNames[] = {"SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"};

char *monthNames[] = {"JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                      "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"};

// Print the day of the week.
// @day    Week day. 0=Sunday to 6=Saturday.
void printDayName(byte day)
{
  Serial.print(dayNames[day]);
}

// Print the month name.
// @day    Week day. 0=Sunday to 6=Saturday.
void printMonthName(byte month)
{
  Serial.print(monthNames[month]);
}
