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
mylog("Dest: ",@transdata);
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

sub handleTemp {
    my $register = shift;
    my $name = shift;
    my $key = shift;

    my ($valid, $value) = CmdRespTemp(0x81, 0x02, $register, 0);
    if ($valid) {
	printf("%s (0x%.02X) = %s\n", $name, $register, $value);
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




#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('20B'),0);
#if ($valid) {print "Radiator return [GT1] 20B=$value\n"} else {print "Error 20B:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('20C'),0);
#if ($valid) {print "Outdoor [GT2] 20C=$value\n"} else {print "Error 20C:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('20B'),0);
#if ($valid) {print "Hot water [GT3] 20D=$value\n"} else {print "Chyba bojler 20D:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('20E'),0);
#if ($valid) {print "Forward [GT4] 20E=$value\n"} else {"Chyba dopredu 20E:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('20F'),0);
#if ($valid) {print "Room [GT5] 20F=$value\n"} else {"Chyba mistnost 20F:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('210'),0);
#if ($valid) {print "Compressor [GT6] 210=$value\n"} else {print "Chyba kompresor 210:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('211'),0);
#if ($valid) {print "Heat fluid out [GT8] 211=$value\n"} else {print "Chyba teply vystup 211:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('212'),0);
#if ($valid) {print "Heat fluid in [GT9] 212=$value\n"} else {print "Chyba teply vstup 212:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('213'),0);
#if ($valid) {print "Cold fluid in [GT10] 213=$value\n"} else {print "Chyba studeny vstup 213:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('214'),0);
#if ($valid) {print "Cold fluid out [GT11] 214=$value\n"} else {print "Chyba teply vystup 214:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('215'),0);
#if ($valid) {print "External hot water [GT3x] 214=$value\n"} else {print "Chyba teply vystup 214:$value\n"}


#($valid,$value)=CmdRespVal(hex('81'),hex('02'),hex('1FF'),0);
#if ($valid) {print "Ground loop pump [P3] 1FF=$value\n"} else {print "Chyba cerp. zem. okr 1FF:$value\n"}
#($valid,$value)=CmdRespVal(hex('81'),hex('02'),hex('200'),0);
#if ($valid) {print "Compresor 200=$value\n"} else {print "Chyba kompresor 200:$value\n"}
#($valid,$value)=CmdRespVal(hex('81'),hex('02'),hex('201'),0);
#if ($valid) {print "Additional heat 3kW 201=$value\n"} else {print "Chyba dotop 3kW 201:$value\n"}
#($valid,$value)=CmdRespVal(hex('81'),hex('02'),hex('202'),0);
#if ($valid) {print "Additional heat 6kW 202=$value\n"} else {print "Chyba dotop 6kW 202:$value\n"}
#($valid,$value)=CmdRespVal(hex('81'),hex('02'),hex('205'),0);
#if ($valid) {print "Radiator pump [P1] 205=$value\n"} else {print "Chyba radiatoroe P1 205:$value\n"}
#($valid,$value)=CmdRespVal(hex('81'),hex('02'),hex('206'),0);
#if ($valid) {print "Heat carrier pump [P2] 206=$value\n"} else {print "Chyba vnitrni P1 206:$value\n"}
#($valid,$value)=CmdRespVal(hex('81'),hex('02'),hex('207'),0);
#if ($valid) {print "Tree-way valve [VXV] 207=$value\n"} else {print "Chyba trojcestny VXV 206:$value\n"}
#($valid,$value)=CmdRespVal(hex('81'),hex('02'),hex('208'),0);
#if ($valid) {print "Alarm 208=$value\n"} else {print "Chyba porucha 208:$value\n"}

#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('6E'),0);
#if ($valid) {print "GT1 Target value 6E=$value\n"} else {print "Chyba GT1 cil 6E:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('6F'),0);
#if ($valid) {print "GT1 On value 6F=$value\n"} else {print "Chyba GT1 zap 6F:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('70'),0);
#if ($valid) {print "GT1 Off value 70=$value\n"} else {print "Chyba GT1 vyp 70:$value\n"}

#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('2B'),0);
#if ($valid) {print "GT3 Target value 2B=$value\n"} else {print "Chyba GT3 cil 2B:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('73'),0);
#if ($valid) {print "GT3 On value 73=$value\n"} else {print "Chyba GT3 zap 73:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('74'),0);
#if ($valid) {print "GT3 Off value 74=$value\n"} else {print "Chyba GT3 vyp 74:$value\n"}

#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('0000'),0);
#if ($valid) {print "Heat curve 0000=$value\n"} else {print "Chyba topna 00:$value\n"}
#($valid,$value)=CmdRespTemp(hex('81'),hex('02'),hex('0001'),0);
#if ($valid) {print "Heat curve fine adj. 01=$value\n"} else {print "Chyba jemne 01:$value\n"}



#my $i;
#foreach $i (hex('0000')..hex('0005'))
#{
# ($valid,$value)=CmdRespVal(hex('81'),hex('00'),$i,0);
# if ($valid) {print "Timer in sec $i=$value\n"} else {print "Chyba Timer $i:$value\n"}
#}

#my $i;
#foreach $i (hex('000')..hex('005'))
#{
# ($valid,$value)=CmdRespVal(hex('81'),hex('04'),$i,0);
# if ($valid) {$value*=10;printf("%.4X=$value\n",$i)} else {printf("Chyba %.4X:$value\n",$i)};
#}

($valid,$value)=CmdRespKey(hex('81'),hex('01'),hex('000B'),1);
if ($valid) {print "Key 3 pressed\n"} else {print "Err key Power:$value\n"}

($valid,$value)=CmdRespDisp(hex('81'),hex('20'),hex('0000'),0);
if ($valid) {print "Disp 0=|$value|\n"} else {print "Chyba disp 0:$value\n"}
($valid,$value)=CmdRespDisp(hex('81'),hex('20'),hex('0001'),0);
if ($valid) {print "Disp 1=|$value|\n"} else {print "Chyba disp 1:$value\n"}
($valid,$value)=CmdRespDisp(hex('81'),hex('20'),hex('0002'),0);
if ($valid) {print "Disp 2=|$value|\n"} else {print "Chyba disp 2:$value\n"}
($valid,$value)=CmdRespDisp(hex('81'),hex('20'),hex('0003'),0);
if ($valid) {print "Disp 3=|$value|\n"} else {print "Chyba disp 3:$value\n"}

portdisconnect();
