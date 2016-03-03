#!/usr/bin/perl

# TODO
# how to handle it ???
#
#if( $^O =~ /Win/io ) {
#	use Win32::SerialPort;
#} else {
	use Device::SerialPort;
#}

use strict;


#my $port=( $^O =~ /Win/io ) ? 'COM7' : '/dev/ttyUSB3';

my $port = "/dev/" . `ls /sys/bus/usb-serial/drivers/cp210x |grep tty`;
chomp($port);



my $PortObj;

sub portconnect {
#my $Configuration_File_Name = '/tmp/ram/port.cfg';
my $Lock_File_Name=( $^O =~ /Win/io ) ? 'C:\lock.ivt' : '/tmp/port.ivt.lock';
my $quiet;

if( $^O =~ /Win/io ) {
	$PortObj = new Win32::SerialPort($port, $quiet, $Lock_File_Name);
} else {
	$PortObj = new Device::SerialPort($port, $quiet, $Lock_File_Name);
}
$PortObj->handshake("none");           # set parameter
$PortObj->baudrate(19200);
$PortObj->parity("none");
$PortObj->databits(8);
$PortObj->stopbits(1);

$PortObj->buffers(100, 100);  # read, write

$PortObj->read_char_time(5);     # avg time between read char
$PortObj->read_const_time(100);  # total = (avg * bytes) + const 
if( $^O =~ /Win/io ) {
        $PortObj->read_interval(100);    # max time between read char (milliseconds)
        $PortObj->write_char_time(5);
        $PortObj->write_const_time(100);
}
        

$PortObj->write_settings || undef $PortObj;

##Old method using file handle, new port object
#print "Can't change Device_Control_Block: $^E\n" unless ($PortObj);
#$PortObj->save($Configuration_File_Name)
#       || warn "Can't save $Configuration_File_Name: $!\n";
#
#$PortObj->close || warn "close failed";
#if( $^O =~ /Win/io ) {
#	$PortObj = tie (*FH, 'Win32::SerialPort', $Configuration_File_Name)
#	       || die "Can't tie using $Configuration_File_Name: $!\n";
#	
#} else {
#	$PortObj = tie (*FH, 'Device::SerialPort', $Configuration_File_Name)
#	       || die "Can't tie using $Configuration_File_Name: $!\n";
#}
if (!defined($PortObj)) {print "Port problem"};
}

sub cmdsend (@) {             # send values (array) to port
        my $znak;
        my @transdata = @_;
        my $count_out;
	foreach $znak (@transdata) {
	  # syswrite FH, chr($znak), 1;
	  $count_out = $PortObj->write(chr($znak));
	  print "write failed\n" unless ($count_out);
	}
}

sub cmdread ($$) {                 # read $max characters with $timeout (number of 0.1s intervals)
	my $done = 0;
	my $cnt = 0;
	my $maxcnt = shift;
	my $to = 0;
	my $maxto = shift;
	my $BlockingFlags;
	my $InBytes;
	my $OutBytes;
	my $LatchErrorFlags;
	my $char;
	my @transdata=();

	do {	
         #$InBytes = sysread(FH,$char,1);
         ($InBytes, $char) = $PortObj->read(1);
         if ($InBytes) {
	  $to=0;
	  $transdata[$cnt]=ord($char);
	  $cnt++;
          #print "R";
         } else {
          select( undef, undef, undef, 0.1 );
          $to++;
          #print "T";
         }
	 if ($maxcnt == $cnt) {$done++};
	 if ($to >= $maxto) {$done++};
	}  while (not $done);
	return @transdata;
}

sub portdisconnect {
$PortObj->close || warn "close failed";
}

sub mylog (@) {
       my $znak;
       my $part;
       my $htext = shift;
       my @transdata = @_;
       print $htext;
	foreach $znak (@transdata) {
         #print "$znak\n";
	 printf(" %.2X",$znak);
	}
	print "\n";
}

sub res2num (@)     # convert received values (array) to temperature
{
   my @pole = @_;
   my $znak = $pole[1] * 16384 + $pole[2] * 128 + $pole[3];
   if ($pole[1] >=2) {$znak -=(65536);}
   #$znak *= 0.1;
   return $znak;
}

sub num2read ($$$$) # prepare values (array) for sending
                    # parameters: addres, command, register, value
{
   my $addr = shift;
   my $cmd  = shift;
   my $reg  = shift;
   my $val  = shift;
   my @pole = ($addr,$cmd,00,00,00,00,00,00,00);
   my $sum = 0;
   my $poc;

   foreach $poc (0..2) {
    $pole[4-$poc] = $reg &  hex('7F');
    $sum = $sum ^ $pole[4-$poc];
    $reg = $reg >> 7;
   }
   foreach $poc (0..2) {
    $pole[7-$poc] = $val &  hex('7F');
    $sum = $sum ^ $pole[7-$poc];
    $val = $val >> 7;
   }
    $pole[8] = $sum;
    return @pole;
}

sub read2reg (@)    # convert values (array) to register
{
    my @pole = @_;
    my $poc;
    my $znak=$pole[2];
    foreach $poc (0..1) {
     $znak = ($znak * 128) + $pole[3+$poc];
    }
    return $znak;
}

sub read2text(@)    # convert 42 bytes array to text
{
    my @pole = @_;
    my $poc;
    my $znak;
    my $text="";
    foreach $poc (0..19) {
     $znak = ($pole[1+($poc*2)] << 4) + $pole[2+($poc*2)];
     $text .= chr($znak);
    }
    return $text;
}

sub ReadVal {
    my @transarray = ();
    my $invalid = "";
    my $value = 0;
    
    my @transdata=cmdread(5,10);
#mylog("Dest: ",@transdata);
    if (@transdata!=5) {$invalid="L"}; # wrong length
    if (!$invalid) {if ($transdata[0]!=hex('01')) {$invalid="H";}} # wrong header
    if (!$invalid) {if ($transdata[4]!=($transdata[1]^$transdata[2]^$transdata[3])) {$invalid="C";}} # wrong checksum

    if (!$invalid) {$value=res2num(@transdata);}
    return ($invalid, $value);
}

sub ReadDispVal {
    my @transarray = ();
    my $invalid = "";
    my $value = 0;
    my $c = 0;
    
    my @transdata=cmdread(42,20);
#mylog("Dest: ",@transdata);
    if (@transdata!=42) {$invalid="L"}; # wrong length
    if (!$invalid) {if ($transdata[0]!=hex('01')) {$invalid="H";}} # wrong header
     foreach my $i (1..40) {
      $c = $c ^ $transdata[$i];
     }
    if (!$invalid) {if ($transdata[41]!=$c) {$invalid="C";}} # wrong checksum

    if (!$invalid) {$value=read2text(@transdata);}
    return ($invalid, $value);
}

sub ReadKeyVal {
    my @transarray = ();
    my $invalid = "";
    my $value = 0;
    
    my @transdata=cmdread(5,10);
    #mylog("Dest: ",@transdata);
    if (@transdata!=1) {$invalid="L"}; # wrong length
    if (!$invalid) {if ($transdata[0]!=hex('01')) {$invalid="H";}} # wrong header
    #if (!$invalid) {if ($transdata[4]!=($transdata[1]^$transdata[2]^$transdata[3])) {$invalid="C";}} # wrong checksum

    if (!$invalid) {$value="OK";}
    return ($invalid, $value);
}



sub SendCmd ($$$$) {
                    # prepare values (array) for sending
                    # parameters: addres, command, register, value
    my $addr = shift;
    my $cmd  = shift;
    my $reg  = shift;
    my $val  = shift;
    cmdsend(num2read($addr,$cmd,$reg,$val));
}

sub CmdRespTemp ($$$$) {# prepare values (array) for sending
                    # parameters: addres, command, register, value
    my $addr = shift;
    my $cmd  = shift;
    my $reg  = shift;
    my $val  = shift;
    my @data = num2read($addr,$cmd,$reg,$val);
    my $invalid;
    my $value;
    my $retrys = 0;
    my $done = 0;
    my $results = "";
#    mylog("address: ", $addr);
#    mylog("cmd: ", $cmd);
#    mylog("reg: ", $reg);
#    mylog("val: ", $val);
#    mylog("Source: ",@data);
    do {	
     cmdsend(@data);
     ($invalid, $value) = ReadVal;
#     print "V:$invalid $value\n";
     if ($invalid) {$results.=$invalid;}
     if (!$invalid) {$done=1};
     if ($invalid) {if ($retrys++>=5) {$done=1;}};
    } while (!$done);
   if (!$invalid) {return (1,0.1 * $value)} else {return (0,$results)};
}

sub CmdRespVal ($$$$) {# prepare values (array) for sending
                    # parameters: addres, command, register, value
    my $addr = shift;
    my $cmd  = shift;
    my $reg  = shift;
    my $val  = shift;
    my @data = num2read($addr,$cmd,$reg,$val);
    my $invalid;
    my $value;
    my $retrys = 0;
    my $done = 0;
    my $results = "";

#    mylog("Source: ",@data);
    do {	
     cmdsend(@data);
     ($invalid, $value) = ReadVal;
#     print "V:$invalid $value\n";
     if ($invalid) {$results.=$invalid;}
     if (!$invalid) {$done=1};
     if ($invalid) {if ($retrys++>=5) {$done=1;}};
    } while (!$done);
   if (!$invalid) {return (1,$value)} else {return (0,$results)};
}

sub CmdRespDisp ($$$$) {# prepare values (array) for sending
                    # parameters: addres, command, register, value
    my $addr = shift;
    my $cmd  = shift;
    my $reg  = shift;
    my $val  = shift;
    my @data = num2read($addr,$cmd,$reg,$val);
    my $invalid;
    my $value;
    my $retrys = 0;
    my $done = 0;
    my $results = "";

#    mylog("Source: ",@data);
    do {	
     cmdsend(@data);
     ($invalid, $value) = ReadDispVal;
#     print "V:$invalid $value\n";
     if ($invalid) {$results.=$invalid;}
     if (!$invalid) {$done=1};
     if ($invalid) {if ($retrys++>=5) {$done=1;}};
    } while (!$done);
   if (!$invalid) {return (1,$value)} else {return (0,$results)};
}

sub CmdRespKey ($$$$) {# prepare values (array) for sending
                    # parameters: addres, command, register, value
    my $addr = shift;
    my $cmd  = shift;
    my $reg  = shift;
    my $val  = shift;
    my @data = num2read($addr,$cmd,$reg,$val);
    my $invalid;
    my $value;

    # keyboard not repeated -> do not know if lost in write or read
    cmdsend(@data);
    ($invalid, $value) = ReadKeyVal;
    if (!$invalid) {return (1,$value)} else {return (0,$invalid)};

}

sub CmdWriteTemp($$$$) {
    my $addr = shift;
    my $cmd  = shift;
    my $reg  = shift;
    my $val  = shift;
    my @data = num2read($addr,$cmd,$reg,$val);
    my $invalid;
    my $value;
    my $retrys = 0;
    my $done = 0;
    my $results = "";
    #mylog("CmdWriteTemp");
    #mylog("address: ", $addr);
    #mylog("cmd: ", $cmd);
    #mylog("reg: ", $reg);
    #mylog("val: ", $val);
    #mylog("Source: ",@data);

    cmdsend(@data);
    ($invalid, $value) = ReadKeyVal;
    #mylog("invalid: $invalid, value: $value");
    if (!$invalid) {return (1,$value)} else {return (0,$invalid)};

}


sub handleTemp {
    my $register = shift;
    my $name = shift;
    my $key = shift;

    my ($valid, $value) = CmdRespTemp(0x81, 0x02, $register, 0);
    if ($valid && $value eq "-48.3") {
	$valid = 0;
    }
    if ($valid) {
	printf("%s (0x%.02X) = %s\n", $name, $register, $value);
	return $value;
    } else {
	printf("Error when obtaining $name (0x%.02X)\n", $name, $register);
    }
}

sub handleValue{
    my $register = shift;
    my $name = shift;
    my $key = shift;

    my ($valid, $value) = CmdRespVal(0x81, 0x02, $register, 0);
    if ($valid) {
	printf("%s (0x%.02X) = %s\n", $name, $register, $value);
	return $value;
    } else {
	printf("Error when obtaining $name (0x%.02X)\n", $name, $register);
    }
}

sub handleUnknown {
    my $register = shift;
    my $name = shift;
    my $key = shift;

    my ($valid, $value) = CmdRespVal(0x81, 0x02, $register, 0);
    if ($valid) {
        
        printf("%s (0x%.02X) = %s temp or %s value\n", $name, $register, 0.1 * $value, $value);
        return $value;
    } else {
        printf("Error when obtaining $name (0x%.02X)\n", $name, $register);
    }
}


sub handleTimer {
    my $register = shift;
    my $name = shift;
    my $key = shift;

    my ($valid, $value) = CmdRespVal(0x81, 0x04, $register, 0);
    if ($valid) {
	printf("%s (0x%.02X) = %s\n", $name, $register, $value);
    } else {
	printf("Error when obtaining $name (0x%.02X)\n", $name, $register);
    }
}

portconnect();
my $valid;
my $value;
my $datum = localtime(time);

################################
# Hmm, that is working -> comented out because I'm debuging not working parts
################################



handleTemp(0x0000, "Heat curve", "heat_curve");
handleTemp(0x0001, "Heat curve find adj", "heat_curve_fine_adj");
handleTemp(0x0002, "Heat curve coupling diff.", "");
handleUnknown(0x0003, "Unknown.", "");
handleUnknown(0x0004, "Unknown.", "");
handleUnknown(0x0005, "Unknown.", "");
handleUnknown(0x0006, "Unknown.", "");
handleUnknown(0x0007, "Unknown.", "");



handleTemp(0x0008, "Adj. curve at -35' out", "");
handleUnknown(0x0009, "Unknown.", "");

handleTemp(0x000A, "Adj. curve at -30' out", "");
handleTemp(0x000C, "Adj. curve at -25' out", "");
handleTemp(0x000E, "Adj. curve at -20' out", "");
handleTemp(0x0010, "Adj. curve at -15' out", "");
handleTemp(0x0012, "Adj. curve at -10' out", "");
handleTemp(0x0014, "Adj. curve at -5' out", "");
handleTemp(0x0016, "Adj. curve at 0' out", "");
handleTemp(0x0018, "Adj. curve at 5' out", "");
handleTemp(0x001A, "Adj. curve at 10' out", "");
handleTemp(0x001C, "Adj. curve at 15' out", "");
handleTemp(0x001E, "Adj. curve at 20' out", "");

handleTemp(0x0021, "Indoor temp setting", "indoor_temp_setting");
handleTemp(0x0022, "Curve infl. by in-temp.", "");
handleUnknown(0x0023, "Unknown.", "");
handleUnknown(0x0024, "Unknown.", "");
handleUnknown(0x0025, "Unknown.", "");
handleUnknown(0x0026, "Unknown.", "");
handleUnknown(0x0027, "Unknown.", "");
handleUnknown(0x0028, "Unknown.", "");
handleUnknown(0x0029, "Unknown.", "");
handleUnknown(0x002a, "Unknown.", "");

handleTemp(0x002B, "GT3 Target value", "gt3_target_value");
handleUnknown(0x002C, "Unknown.", "");
handleUnknown(0x002d, "Unknown.", "");
handleUnknown(0x002e, "Unknown.", "");
handleUnknown(0x002f, "Unknown.", "");
for (my $i = 0x30; $i < 0x6a; $i++) {
  handleUnknown($i, "Unknown.", "");
}

handleUnknown(0x006a, "unknown", "add_heat_power_in_percent");
handleUnknown(0x006b, "unknown", "add_heat_power_in_percent");

handleTemp(0x006C, "Add heat power in %", "add_heat_power_in_percent");
handleTemp(0x006D, "GT4 Target value", "gt4_target_value");
handleTemp(0x006E, "GT1 Target value", "gt1_target_value");
handleTemp(0x006F, "GT1 On value", "gt1_on_value");
handleTemp(0x0070, "GT1 Off value", "gt1_off_value");
handleTemp(0x0073, "GT3 On value", "gt3_on_value");
handleTemp(0x0074, "GT3 Off value", "gt3_off_value");

for (my $i = 0x75; $i < 0x84; $i++) {
  handleUnknown($i, "Unknown.", "");
}



handleTimer(0x0000, "Add heat timer in sec.", "add_heat_time_in_sec");


portdisconnect();

