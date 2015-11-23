// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0] : port p_scl = XS1_PORT_1E;         //interface ports to accelerometer
on tile[0] : port p_sda = XS1_PORT_1F;
on tile[0] : port buttons = XS1_PORT_4E;       //port to access xCore-200 buttons
on tile[0] : port leds = XS1_PORT_4F;          //port to access xCore-200 LEDs

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for accelerometer
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////

void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
//    printf( "-%4.1d ", line[ x ] ); //show image values
    }
//  printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream:Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void worker(chanend toDist) { //first attempt at worker function, assuming all tiles have a "border" of read-only tiles around them.
  uchar valMap[IMWD][IMHT];
  while (1) {
    for( int y = 0; y < IMHT; y++ ) {
      for( int x = 0; x < IMWD; x++ ) {
        toDist :> valMap[x][y];
      }
    }
    int count = 0;
    uchar val;
    for (int y = 0; y < IMHT; y++) {
      for (int x = 0; x < IMWD; x++) {
        count = 0;
        for (int i = y-1; i <= y+1; i++) {
          for (int j = x-1; j <= x+1; j++) {
            count += valMap[(j+IMWD)%IMWD][(i+IMWD)%IMWD];
          }
        }
        if ((valMap[x][y] == 255 && (count == 765 || count == 1020)) // 765 = 255*3, 1020 = 255*4 (given block is surrounded by 2/3 live pixels plus itself).
          ||(valMap[x][y] == 0   && count == 765))
        {
          val = 255;
        }
        else {
          val = 0;
        }
        toDist <: val;
      }
    }
  }
}


void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend toWorker, chanend fromButtons, chanend toLED)
{
  uchar buttonval = 0;
  uchar valMap[IMWD][IMHT];
  int tilt = 0;
  int round = 0;

  printf( "ProcessImage:Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for Button Press...\n" );


  while (buttonval != 14) {
    fromButtons :> buttonval;
    toLED <: 4;
  }

  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> valMap[x][y];
    }
  }
  while (1) {
    fromAcc :> tilt;
    if (round == 200) {
      toLED <: 0;
      for( int y = 0; y < IMHT; y++ ) {
        for( int x = 0; x < IMWD; x++ ) {
          c_out <: valMap[x][y];
        }
      }
      while (tilt != 0) fromAcc :> tilt;
    }

    for( int y = 0; y < IMHT; y++ ) {
      for( int x = 0; x < IMWD; x++ ) {
        toWorker <: valMap[x][y];
      }
    }

    for( int y = 0; y < IMHT; y++ ) {
      for( int x = 0; x < IMWD; x++ ) {
        toWorker :> valMap[x][y];
      }
    }
    round++;
    printf( "Round %d completed...\n", round );
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataOutStream:Start...\n" );

  //Open PGM file
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream:Error opening %s\n.", outfname );
    return;
  }
   //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> line[ x ];
    }
    _writeoutline( line, IMWD );
  }

  //Close the PGM image
  _closeoutpgm();

  printf( "DataOutStream:Done...\n" );
  return;
}

void buttonListener(in port b, chanend toDist) {
  uchar r;
  while (1) {
    b when pinseq(15)  :> r;    // check that no button is pressed
    b when pinsneq(15) :> r;    // check if some buttons are pressed
    if ((r==13) || (r==14))    // if either button is pressed //SW1 = 14 SW2 = 13
    toDist <: r;
  }
}

int showLEDs(port p, chanend fromDist) {
  int pattern; //1st bit...separate green LED
               //2nd bit...blue LED
               //3rd bit...green LED
               //4th bit...red LED

  while (1) {
      printf("newpattern\n");
      fromDist :> pattern;
      p <: pattern;
  }

  return 0;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read accelerometer, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void accelerometer(client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the accelerometer x-axis forever
  while (1) {

    //check until new accelerometer data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (x > 30) toDist <: 1;
    else toDist <: 0;
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

  i2c_master_if i2c[1];               //interface to accelerometer

  chan c_inIO, c_outIO, c_control, c_workerComms, buttonToDist, distToLED;    //extend your channel definitions here

  par {
      on tile[0]:  i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing accelerometer data
      on tile[0]:  accelerometer(i2c[0],c_control);        //client thread reading accelerometer data
      on tile[0]:  DataInStream("test.pgm", c_inIO);          //thread to read in a PGM image
      on tile[0]:  DataOutStream("testout.pgm", c_outIO);       //thread to write out a PGM image
      on tile[0]:  distributor(c_inIO, c_outIO, c_control, c_workerComms, buttonToDist, distToLED);//thread to coordinate work on image
      on tile[1]:  worker(c_workerComms);
      on tile[0]:  buttonListener(buttons, buttonToDist);
      on tile[0]:  showLEDs(leds, distToLED);
  }

  return 0;
}
