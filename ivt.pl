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


print "using tty $port\n";

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
print "portobj: " . $PortObj;
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
	if ($key ne "") {
	    my $cmd = "zabbix_sender -z ubuntu.juhonkoti.net -s nest -k ivt.$key -o $value";
	    `$cmd`;
	}
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
	if ($key ne "") {
	    my $cmd = "zabbix_sender -z ubuntu.juhonkoti.net -s nest -k ivt.$key -o $value";
	    `$cmd`;
	}
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
	if ($key ne "") {
	    my $cmd = "zabbix_sender -z ubuntu.juhonkoti.net -s nest -k ivt.$key -o $value";
	    `$cmd`;
	}
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

my $gt1_current_value = handleTemp(0x0209, "Radiator return [GT1]", "radiator_return_gt1");
handleTemp(0x020A, "Outdoor [GT2]", "outdoor_gt2");
handleTemp(0x020B, "Hot water [GT3]", "hot_water_gt3");
handleTemp(0x020C, "Forward [GT4]", "forward_gt4");
my $room_temp = handleTemp(0x020D, "Room [GT5]", "room_gt5");
handleTemp(0x020E, "Compressor [GT6]", "compressor_gt6");
handleTemp(0x020F, "Heat fluid out [GT8]", "heat_fluid_out_gt8");
handleTemp(0x0210, "Heat fluid in [GT9]", "heat_fluid_in_gt9");
handleTemp(0x0211, "Cold fluid in [GT10]", "cold_fluid_in_gt10");
handleTemp(0x0212, "Cold fluid out [GT11]", "cold_fluid_out_gt11");
#handleTemp(0x0213, "External hot water [GT3x]", "external_hot_water_gt3x");

handleValue(0x01FD, "Ground loop pump [P3]", "ground_loop_pump_p3");
my $compressor = handleValue(0x01FE, "Compresor", "compressor");
my $additional_heat_3kw = handleValue(0x01FF, "Additional heat 3kW", "additional_heat_3kw");
my $additional_heat_6kw = handleValue(0x0200, "Additional heat 6kW", "additional_heat_6kw");
handleValue(0x0203, "Radiator pump [P1]", "radiator_pump_p1");
handleValue(0x0204, "Heat carrier pump [P2]", "heat_carrier_pump_p2");
handleValue(0x0205, "Three-way valve [VXV]", "three_way_valve");
handleValue(0x0206, "Alarm", "alarm");

handleValue(0x002A, "2.2 interval for hot water peak * 10 minutes", "hot_water_peak_interval_10mins");
handleValue(0x0052, "8.1 additional heat delay", "additional_heat_delay_secs");

my $gt1_target_value = handleTemp(0x006E, "GT1 Target value", "gt1_target_value");
handleTemp(0x006F, "GT1 On value", "gt1_on_value");
handleTemp(0x0070, "GT1 Off value", "gt1_off_value");
my $current_hot_water = handleTemp(0x002B, "GT3 (hot water) Target value", "gt3_target_value");
handleTemp(0x0073, "GT3 On value", "gt3_on_value");
handleTemp(0x0074, "GT3 Off value", "gt3_off_value");
handleTemp(0x006D, "GT4 Target value", "gt4_target_value");
handleTemp(0x006C, "Add heat power in %", "add_heat_power_in_percent");

my $temp_curve = handleTemp(0x0000, "Heat curve", "heat_curve");
my $fine_adj = handleTemp(0x0001, "Heat curve find adj", "heat_curve_fine_adj");
my $indoor_temp_setting = handleTemp(0x0021, "Indoor temp setting", "indoor_temp_setting");
my $current_indoor_temp_influence = handleTemp(0x0022, "Curve infl. by in-temp.", "");
handleTemp(0x001E, "Adj. curve at 20' out", "");
handleTemp(0x001C, "Adj. curve at 15' out", "");
handleTemp(0x001A, "Adj. curve at 10' out", "");
handleTemp(0x0018, "Adj. curve at 5' out", "");
handleTemp(0x0016, "Adj. curve at 0' out", "");
handleTemp(0x0014, "Adj. curve at -5' out", "");
handleTemp(0x0012, "Adj. curve at -10' out", "");
handleTemp(0x0010, "Adj. curve at -15' out", "");
handleTemp(0x000E, "Adj. curve at -20' out", "");
handleTemp(0x000C, "Adj. curve at -25' out", "");
handleTemp(0x000A, "Adj. curve at -30' out", "");
handleTemp(0x0008, "Adj. curve at -35' out", "");
handleTemp(0x0002, "Heat curve coupling diff.", "");

handleTimer(0x0000, "Add heat timer in sec.", "add_heat_time_in_sec");


$gt1_target_value = int($gt1_target_value * 10.0);
$gt1_current_value = int($gt1_current_value * 10.0);
$indoor_temp_setting = int($indoor_temp_setting * 10.0);
$fine_adj = int($fine_adj * 10.0);
$additional_heat_3kw = int($additional_heat_3kw);
$additional_heat_6kw = int($additional_heat_6kw);
$compressor = int($compressor);
$room_temp = int($room_temp * 10.0);
$current_hot_water = int($current_hot_water * 10.0);
$current_indoor_temp_influence = int($current_indoor_temp_influence * 10.0);

printf("current temp curve: %s\n", $temp_curve);

$temp_curve = int($temp_curve * 10.0);

printf("gt1_target_value: %d, gt1_current_value: %d\n", $gt1_target_value, $gt1_current_value);
my $mode;
chomp($mode = `cat /tmp/mode.txt`);

printf("Current mode: '%s'\n", $mode);

###
### Settings for warmup mode
###
my $target_temp = 210;
my $warming_up_temp_curve = 20;
my $warming_up_indoor_temp_influence = 0;

###
### Settings for away mode
###
my $away_hot_water = 450;
my $away_target_temp = 140;
my $away_temp_curve = 150;
my $away_fine_adj = -30;
my $away_indoor_temp_influence = 1;

###
### At home mode
###
my $athome_target_temp = 210;
my $athome_hot_water = 510;
my $athome_temp_curve = 550;
my $athome_fine_adj = 0;
my $athome_indoor_temp_influence = 5;


if ($mode eq "warmup") {
        if ($current_hot_water != $athome_hot_water) {
                printf("Settings warmup mode hot water target temp to %d (same as in athome mode)\n", $athome_hot_water);
                CmdWriteTemp(hex('81'), hex('03'), hex('2B'), $athome_hot_water);
        }

        if ($current_indoor_temp_influence != $warming_up_indoor_temp_influence) {
                printf("Setting away mode indoor temp influence to %d\n", $warming_up_indoor_temp_influence);
                CmdWriteTemp(hex('81'), hex('03'), hex('22'), $warming_up_indoor_temp_influence);
        }

	if ($temp_curve != $warming_up_temp_curve) {
		printf("Setting warming up mode temp curve from %d to %d\n", $temp_curve, $warming_up_temp_curve);
		CmdWriteTemp(hex('81'), hex('03'), hex('00'), $warming_up_temp_curve); # original: 55, temp curve
	}

	printf("House is in warming up mode. target temp is %d. indoor temp setting is %d, fine adjust is currently set to %d\n", $athome_target_temp, $indoor_temp_setting, $fine_adj);
	if ($room_temp >= $athome_target_temp) {
		printf("Reached target temperature\n");
		my $new_fine_adj = $fine_adj - 10;
		if ($new_fine_adj < -100) {
		  $new_fine_adj = -100;
		}
		CmdWriteTemp(hex('81'), hex('03'), hex('01'), $new_fine_adj); # original: 1, temp fine adjust

	} elsif ($additional_heat_3kw == 1 or $additional_heat_6kw == 1) {
		printf("Additional heat is on. Turning target temp down until it turns off.\n");
		my $new_fine_adj = $fine_adj - 10;
		if ($new_fine_adj < -100) {
		  $new_fine_adj = -100;
		}	
		CmdWriteTemp(hex('81'), hex('03'), hex('01'), $new_fine_adj); # original: 1, temp fine adjust

	# if current target is not high enough then ramp target up
	} elsif ($gt1_current_value > $gt1_target_value && $gt1_current_value < 500) {
 	  my $new_fine_adj = $fine_adj + 20;
	  if ($new_fine_adj > 100) {
	    $new_fine_adj = 100;
	  }
          printf("Current GT1 value (%d) is over the target (%d). Changing fine adj from %d to %d\n", $gt1_current_value, $gt1_target_value, $fine_adj, $new_fine_adj);
	  CmdWriteTemp(hex('81'), hex('03'), hex('01'), $new_fine_adj); # original: 1, temp fine adjust

	# if current target is too high then ramp it back down
	} elsif ($gt1_current_value + 40< $gt1_target_value && $gt1_current_value > 20) {
	  my $new_fine_adj = $fine_adj - 20;
	  if ($new_fine_adj < -100) {
	    $new_fine_adj = -100;
	  }
	  printf("Current GT1 value (%d) is less than target (%d), Changing fine adj from %d to %d\n", $gt1_current_value, $gt1_target_value, $fine_adj, $new_fine_adj);
	  CmdWriteTemp(hex('81'), hex('03'), hex('01'), $new_fine_adj); # original: 1, temp fine adjust
	} else {
	  printf("Current GT1 value (%d) is within bounds of current GT1 return (%d)\n", $gt1_target_value, $gt1_current_value);
	}
	handleTemp(0x006E, "New GT1 Target value", "gt1_target_value");
} elsif ($mode eq "away") {
        if ($indoor_temp_setting != $away_target_temp) {
                printf("Setting away mode target temp to %d\n", $away_target_temp);
                CmdWriteTemp(hex('81'), hex('03'), hex('21'), $away_target_temp);
        }

	if ($current_hot_water != $away_hot_water) {
		printf("Setting away mode hot water target temp to %d\n", $away_hot_water);
		CmdWriteTemp(hex('81'), hex('03'), hex('2B'), $away_hot_water);
	}
        if ($temp_curve != $away_temp_curve) {
                printf("Setting away mode temp curve to %d\n", $away_temp_curve);
                #CmdWriteTemp(hex('81'), hex('03'), hex('00'), $away_temp_curve); 
        }

	if ($fine_adj != $away_fine_adj) {
		printf("Setting away mode fine adjust to %d\n", $away_fine_adj);
		CmdWriteTemp(hex('81'), hex('03'), hex('01'), $away_fine_adj);
	}

	if ($current_indoor_temp_influence != $away_indoor_temp_influence) {
		printf("Setting away mode indoor temp influence to %d\n", $away_indoor_temp_influence);
		CmdWriteTemp(hex('81'), hex('03'), hex('22'), $away_indoor_temp_influence);
	}
} elsif ($mode eq "athome") {
	if ($indoor_temp_setting != $athome_target_temp) {
                printf("Settings athome mode target temp to %d\n", $athome_target_temp);
                CmdWriteTemp(hex('81'), hex('03'), hex('21'), $athome_target_temp);
	}


        if ($current_hot_water != $athome_hot_water) {
                printf("Settings athome mode hot water target temp to %d\n", $athome_hot_water);
                CmdWriteTemp(hex('81'), hex('03'), hex('2B'), $athome_hot_water);
        }
        if ($temp_curve != $athome_temp_curve) {
                printf("Setting athome mode temp curve to %d\n", $athome_temp_curve);
                #CmdWriteTemp(hex('81'), hex('03'), hex('00'), $athome_temp_curve);
        }

        if ($fine_adj != $athome_fine_adj) {
                printf("Setting athome mode fine adjust to %d\n", $athome_fine_adj);
                CmdWriteTemp(hex('81'), hex('03'), hex('01'), $athome_fine_adj);
        }

        if ($current_indoor_temp_influence != $athome_indoor_temp_influence) {
                printf("Setting athome mode indoor temp influence to %d\n", $athome_indoor_temp_influence);
                CmdWriteTemp(hex('81'), hex('03'), hex('22'), $athome_indoor_temp_influence);
        }


}



print "== $datum ==\n==============================\n";
portdisconnect();

