#!/usr/bin/perl
# MagicPO::Parser
# Copyright (C) Eskild Hustvedt 2007, 2008
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package MagicPO::Parser;
use strict;
use warnings;
use constant { true => 1, false => 0 };
use Carp;
our $VERSION;
$VERSION = '0.4';
our $RCSREV;
$RCSREV = '$Id$';

# Purpose: Create a new object
# Usage: $obj = MagicPO::Parser->new(file,progressioncallback?, NoLastTranslator);
# 	file is the file to read
# 	progressioncallback is a coderef that is called each time either
# 		loading or writing a file has progressed. It can be undef.
#	NoLastTranslator is a boolean, if true then MagicPO::Parser will not update
#		Last-Translator.
sub new
{
	my $this = shift;
	my $file = shift;
	$this = {};
	$this->{file} = $file;
	$this->{progressionCallback} = shift;
	$this->{LastTranslator} = shift(@_) ? false : true;
	$this->{lineno} = 0;
	$this->{ReplaceLastID} = false;
	$this->{DirtyEqualsFuzzy} = false;
	$this->{dirty} = {};
	bless($this,'MagicPO::Parser');
	$this->{Lookup} = {};
	$this->{PoFile} = {};
	$this->{IDS} = 0;
	$this->_LoadFile($file);
	return($this);
}

# Purpose: Write a po-file
# Usage: obj->write(file);
sub write
{
	my $this = shift;
	my $filename = shift;
	return $this->_WriteFile($filename);
}

# Purpose: Merge one MagicPO::Parser object with another
# Usage: obj->mergeobject(otherobj,replaceFuzzy?);
sub mergeobject
{
	my $this = shift;
	my $otherObj = shift;
	my $replaceFuzzy = shift;
	my $lookupErrors = 0;
	# Process every string in otherObj.
	# If the string does not exist in this object, add it (at the end)
	foreach my $string (keys(%{$otherObj->{Lookup}}))
	{
		if(not defined $string)
		{
			$this->_perr("Got an undef string during merge. This is almost certainly a bug.\n");
			next;
		}
		my $thisNo = $this->{Lookup}{$string};
		my $othNo = $otherObj->{Lookup}{$string};
		if(not $thisNo)
		{
			$lookupErrors++;
			if ($lookupErrors == 10)
			{
				print "\n";$this->_perr("Many lookup errors. The po file is probably not up to date, or completely different from the original file. Will continue processing, but the outcome will most likely not be very useful.\n");
			}
			elsif(not $lookupErrors > 10)
			{
				$this->_perr("Strange, unable to look up '$string': po-file not up to date? Skipping this string.\n");
			}
			next;
		}
		# First check if it doesn't exist. In this case we simply add it.
		if(not $this->{PoFile}{$thisNo})
		{
			$this->{IDS}++;
			$this->{PoFile}{$this->{IDS}} = $otherObj->{PoFile}{$otherObj->{Lookup}{$string}};
			# TODO: Should we replace this by a call to _addToLookup()?
			$this->{Lookup}{$string}= $this->{IDS};
			$this->markdirty($this->{IDS});
		}
		# Then check if it /exists/, but is fuzzy (and our source-string isn't)
		elsif($replaceFuzzy and $this->{PoFile}{$thisNo}{'magicpo-statusflags'}{'fuzzy'} and not $otherObj->{PoFile}{$thisNo}{'magicpo-statusflags'}{'fuzzy'})
		{
			delete($this->{PoFile}{$thisNo});
			$this->{PoFile}{$thisNo} = $otherObj->{PoFile}{$otherObj->{Lookup}{$string}};
			# This should already be there, but won't hurt to make sure
			$this->{Lookup}{$string}= $thisNo;
			$this->markdirty($thisNo);
		}
		# Finally, if none of these were true, we iterate through each of msgstr.* and compare those,
		# adding if needed.
		else
		{
			if(not $othNo)
			{
				$this->_perr("Very strange, unable to look up '$string' in other merging object. This should never happen. This is likely a bug. Skipping string, expect problems.\n");
				next;
			}
			foreach my $type(keys(%{$otherObj->{PoFile}{$othNo}}))
			{
				next if not $type =~ /^msgstr/;
				# Check emptyness
				if(not $this->{PoFile}{$thisNo}{$type} =~ /\S/)
				{
					$this->{PoFile}{$thisNo}{$type} = $otherObj->{PoFile}{$othNo}{$type};
					$this->markdirty($thisNo);
				}
			}
		}
	}
	if($lookupErrors > 10)
	{
		$this->_perr("Encountered a total of $lookupErrors lookup errors.\n");
	}
	return true;
}

# Purpose: Mark an msgid as fuzzy
# Usage: obj->markfuzzy(msgid);
sub markfuzzy
{
	my $this = shift;
	my $id = shift;
	my $isDirty = shift;
	my $real_id = $id;

	if ($id =~ /\D/ or not defined($this->{PoFile}{$id}))
	{
		$real_id = $this->{Lookup}{$id};
	}
	if(not $real_id)
	{
		carp("msgid '$id' not found");
		return(false);
	}
	# Don't bother continuing if it's already fuzzy
	if ($this->{PoFile}{$real_id}{'magicpo-statusflags'}{'fuzzy'})
	{
		return(true);
	}
	# Now check for a nonempty msgstr. If we don't find one then we don't mark it as fuzzy.
	my $msgstrExisted = false;
	foreach my $str (qw(msgstr msgstr[0] msgstr[1] msgstr_plural))
	{
		if(defined($this->{PoFile}{$real_id}{$str}))
		{
			$msgstrExisted = true;
			if(length($this->{PoFile}{$real_id}{$str}) > 0)
			{
				$this->{PoFile}{$real_id}{'magicpo-statusflags'}{'fuzzy'} = true;
				last;
			}
		}
	}
	# This is a safety check for msgstr, if it doesn't exist then we need to whine and
	# find out why.
	if(not $msgstrExisted)
	{
		$this->_perr("msgstr appears to be missing for ID $real_id. This is most likely a bug in MagicPO (or an issue with your PO-file).\n");
	}
	# If we're not being called by markdirty() then call it.
	if (!$isDirty)
	{
		$this->markdirty($real_id);
	}
	return(true);
}

# Purpose: Mark a string as dirty (changed)
# Usage: obj->markdirty(ID or msgid);
sub markdirty
{
	my $this = shift;
	my $id = shift;
	if ($id =~ /\D/)
	{
		my $origid = $id;
		$id = $this->{Lookup}{$id};
		if(not $id)
		{
			carp("msgid '$origid' not found");
			return(false);
		}
	}
	$this->{dirty}{$id} = true;
	if ($this->{DirtyEqualsFuzzy})
	{
		$this->markfuzzy($id,true);
	}
	return true;
}

# Purpose: Set the 'markdirty' mode
# Usage: obj->markdirtymode(MODE);
# MODE is one of:
# 	normal		- standard, don't do anything special
# 	fuzzy		- mark strings that are marked as dirty as fuzzy
sub markdirtymode
{
	my $this = shift;
	my $mode = shift;
	if ($mode eq 'fuzzy')
	{
		$this->{DirtyEqualsFuzzy} = true;
	}
	else
	{
		$this->{DirtyEqualsFuzzy} = false;
	}
	return true;
}

# Purpose: Add a string
# Usage: obj->addstring(MSG);
sub addstring
{
	my $this = shift;
	my $msg = shift;

	my $ID = $this->{IDS};
	$ID++;
	$this->{PoFile}{$ID} = $msg;
	if (defined $this->{Lookup}{$msg->{msgid}})
	{
		carp('Multiple identical strings detected. This SHOULD BE HANDLED by the app, not the module. Acting as though this was not detected and happily adding the dupe. Bad stuff might happen.');
	}
	$this->{IDS} = $ID;
	$this->_addToLookup($ID,false);
	return true;
}

# Purpose: Search for a string
# Usage: my $result = obj->search(field,string);
#  Note: Running this operation once or twice on a file is rather fast, but
#        do not run it often as that gets slow very quickly. It ignores the
#        msgid lookup cache.
sub search
{
	my $this = shift;
	my $field = shift;
	my $searchfor = shift;
	foreach my $ent (keys %{$this->{PoFile}})
	{
		if ($this->{PoFile}{$ent}{$field})
		{
			if ($this->{PoFile}{$ent}{$field} eq $searchfor)
			{
				return $ent;
			}
		}
	}
	# Fail
	return;
}

# Purpose: Get a lookup string for ID
# Usage: my $string = obj->getLookup(ID);
sub getLookup
{
	my $this = shift;
	my $ID = shift;
	my $lookupString;

	if (not defined $this->{PoFile}{$ID})
	{
		return;
	}

	if (defined $this->{PoFile}{$ID}{'msgctxt'} and length($this->{PoFile}{$ID}{'msgctxt'}))
	{
		$lookupString = $this->{PoFile}{$ID}{'msgctxt'}.' '.$this->{PoFile}{$ID}{'msgid'};
	}
	else
	{
		$lookupString = $this->{PoFile}{$ID}{'msgid'};
	}
	return $lookupString;
}

# Purpose: Get contents from a line in a po-file (without "" padding and such)
# Usage: $line = _GetLineContents($line);
sub _GetLineContents
{
	my $this = shift;
	my $line = shift;
	$line =~ s/^[^"]+//;
	if(not $line =~ s/^\s*"(.*)"\s*$/$1/)
	{
		$this->_perr("Line not well-formatted. Po-file appears corrupt (unable to fetch contents through usual methods, attempting alternate). Expect problems.\n");
		# Fall back to alternate parsing attempt
		$line =~ s/^\s*"//;
		$line =~ s/"\s*$//;
		if (not $line =~ /\S/)
		{
			$this->_perr("Line either empty or unparseable. Setting its value to ''\n");
			$line = '';
		}
	}
	return($line);
}

# Purpose: Get line contents and name from a line in a po-file
# Usage: ($type,$contents) = _GetPrimaryLine($line);
sub _GetPrimaryLine
{
	my $this = shift;
	my $line = shift;
	my $contents = $this->_GetLineContents($line);
	# Fetch the type
	my $type = $line;
	if(not $type =~ s/^\s*([^"]+)".*/$1/ or not $line =~ /^\s*[\w\d\[\]]+\s*"/)
	{
		$this->_perr("Line not well-formatted. Po-file appears corrupt (invalid quoting). Will attempt to repair, but expect problems.\n");
		$contents = $line;
		$contents =~ s/^\s*"//;
		$contents =~ s/"\s*$//;
		$type = '';
	}
	else
	{
		$type =~ s/\s+//;
	}
	return($type,$contents);
}

# Purpose: Simple status flags parser
# Usage: $scalar = _ParseStatusFlags(line);
sub _ParseStatusFlags
{
	my $line = shift;
	$line =~ s/^#,//;
	my %Flags;
	foreach my $part(split(/,/,$line))
	{
		$part =~ s/\s+//g;
		if(length($part))
		{
			$Flags{$part} = true;
		}
	}
	return(\%Flags);
}

# Purpose: Write info about parser errors or warnings
# Usage: obj->_perr(MSG);
sub _perr
{
	my $this = shift;
	my $message = shift;
	my $near = shift;
	if ($this->{lineno})
	{
		if ($near)
		{
			$this->_err($this->{file}.' near line '.$this->{lineno}.': '.$message);
		}
		else
		{
			$this->_err($this->{file}.'      line '.$this->{lineno}.': '.$message);
		}
	}
	else
	{
		$this->_err($this->{file}.'           : '.$message);
	}
	if (defined($ENV{MAGICPO_P_CALLT}) and $ENV{MAGICPO_P_CALLT})
	{
		print 'Error from: '.(caller(1))[3].' line '.(caller(1))[2]."\n";
	}
	return true;
}

# Purpose: Write an error to STDERR. Always returns false so that you can
# 	return this directly to caller.
# Usage: obj->_err(MSG);
sub _err
{
	my $obj = shift;
	my $err = shift;
	$err =~ s/\n$//;
	warn($err."\n");
	return false;
}

# Purpose: Load a po-file
# Usage: $this->_LoadFile(file);
sub _LoadFile
{
	my $this = shift;
	my $file = shift;

	my $Current;
	my $CurrentVal;
	my $ID = 0;
	# This keeps track of the current comments
	my $CurrComments = '';
	# This keeps track of the current #| lines
	my $CurrPrevTrans = '';
	# This keeps track of statusflags, ie. fuzzy
	my $CurrStatus;
	# This does the same, but with one difference, this one gets
	# newlines added. This so that ENDINGCOMMENTS gets formatted properly
	my $FormattedComments = '';
	# This contains the *raw* part of a string
	my $RawContents;
	# Open the file (in UTF8 mode)
	open(my $in, '<',$file) or return $this->_err("Failed to open '$file' for reading: $!");

	# Read each line and process it
	while(my $line = <$in>)
	{
		# Progress callback
		if (defined $this->{progressionCallback})
		{
			$this->{progressionCallback}->();
		}

		$this->{lineno}++;
		# If the line only had newlines then add to FormattedComments and skip it
		if (not $line =~ /\S/)
		{
			$FormattedComments .= "\n";
			next;
		}
		# Comments
		if ($line =~  /^\s*#/)
		{
			if ($line =~ /^\s*#,/)
			{
				$CurrStatus = _ParseStatusFlags($line);
			}
			elsif ($line =~ /^\s*#\|/)
			{
				$CurrPrevTrans .= $line;
			}
			else
			{
				$CurrComments .= $line;
			}
			$FormattedComments .= $line;
		}
		# New type
		elsif ($line =~ /^\s*[^"]/)
		{
			if (not defined($Current) or $Current =~ /^msgstr/ and not $line =~ /^\s*msgstr/)
			{
				# If the ReplaceLastID flag is set, OR the msgid of the last ID is empty, then use
				# that ID.
				if ((not $ID == 1 and not $ID == 0) and ($this->{ReplaceLastID} or (not defined($this->{PoFile}{$ID}{'msgid'}) or not length($this->{PoFile}{$ID}{'msgid'}))))
				{
					if (not $this->{ReplaceLastID})
					{
						$this->_perr("detected corrupt msgid (empty). Po-file corrupt. This is bad. Entire section discarded.\n",true);
					}
					delete($this->{PoFile}{$ID});
					# Reset ReplaceLastID
					$this->{ReplaceLastID} = false;
					# Reset rawcontents
					$RawContents = undef;
				}
				# If not, bump the ID and on to the next one
				else
				{
					if((not defined $this->{PoFile}{$ID} or not defined $this->{PoFile}{$ID}{'msgid'}) and not $ID == 0)
					{
						$this->_perr("No msgid read (for ID $ID). This is bad, either the po-file is corrupt or this is a bug in the parser\n",true);
					}
					if ($RawContents)
					{
						$this->{PoFile}{$ID}{'magicpo-raw'} = $RawContents;
					}
					if(not $ID == 0)
					{
						$this->_addToLookup($ID,true);
					}
					$RawContents = $line;
					$ID++;
				}
				chomp($line);
				# Add comments if set
				if (length($CurrComments))
				{
					$this->{PoFile}{$ID}{'magicpo-comments'} = $CurrComments;
				}
				# Add status if set
				if (defined($CurrStatus))
				{
					$this->{PoFile}{$ID}{'magicpo-statusflags'} = $CurrStatus;
				}
				# Add #| if set
				if (length($CurrPrevTrans))
				{
					$this->{PoFile}{$ID}{'magicpo-prevtrans'} = $CurrPrevTrans;
				}
				# Add raw comments
				if(length($FormattedComments))
				{
					$this->{PoFile}{$ID}{'magicpo-rawcomments'} = $FormattedComments;
				}
				# Null them out
				$CurrStatus = undef;
				$CurrComments = '';
				$CurrPrevTrans = '';
				$FormattedComments = '';
				# Remove leading newline
				foreach my $var(keys(%{$this->{PoFile}{$ID}}))
				{
					if(not defined($this->{PoFile}{$ID}{$var}))
					{
						$this->_perr("Parser bug: var \"$var\" was undef! Skipping.\n");
					}
					else
					{
						$this->{PoFile}{$ID}{$var} =~ s/\n+$//;
					}
				}
			}
			else
			{
				$RawContents .= $line;
				chomp($line);
				if (defined($Current) and $Current eq 'msgid')
				{
					# Remove leading newline
					$this->{PoFile}{$ID}{'msgid'} =~ s/\n+$//;
				}
			}
			my ($Type,$Contents) = $this->_GetPrimaryLine($line);
			# If type is '' then it's the parser attempting to fix syntax errors, so
			# append that to current.
			if ($Type eq '')
			{
				# Make sure that the contents are something
				if($Contents =~ /\S/ and defined($Current))
				{
					# We've probably bumped ID, don't.
					$ID--;
					$this->{PoFile}{$ID}{$Current} .= $Contents;
				}
				# If not then the line isn't usable, on to the next
				else
				{
					$this->_perr("Line unusable\n");
					next;
				}
			}
			else
			{
				# If msgid is empty and our id isn't 1 then we can't use this, so set the
				# ReplaceLastID flag.
				if (defined($this->{PoFile}{$ID}{'msgid'}) and not length($this->{PoFile}{$ID}{'msgid'}) and not $ID == 1)
				{
					$this->_perr("msgid corrupt (empty). Po-file corrupt. This is bad. Entire section discarded.\n",true);
					$this->{ReplaceLastID} = true;
				}
				# Finally, do what we are required to do, add the data.
				if ($line =~ /^\s*$Type/ and defined($this->{PoFile}{$ID}{$Type}))
				{
					$this->_err("MagicPO::Parser bug: adding '$Type' for the second time. This is bad, attempting to work around it by bumping string ID.");
					$ID++;
				}
				$Current = $Type;
				$this->{PoFile}{$ID}{$Current} .= $Contents;
			}
		}
		# Continuation of another string
		else
		{
			if(not $Current)
			{
				$this->_perr('Parser error: no current line information found. This is a bug in the parser or an invalid PO-file. Skipping line.'."\n",true);
			}
			else
			{
				$RawContents .= $line;
				chomp($line);
				$this->{PoFile}{$ID}{$Current} .= $this->_GetLineContents($line);
			}
		}
	}
	# Close it
	close($in) or carp("Failed to close filehandle for $file: $!");
	# Add the last ID to the lookup table
	$this->_addToLookup($ID,true);
	# If we have comments here that have not been purged, put them in ENDINGCOMMENTS
	if (length($FormattedComments))
	{
		$this->{ENDINGCOMMENTS} = $FormattedComments;
	}
	delete($this->{lineno});
	$this->{IDS} = $ID;
	return true;
}

# Purpose: Format an output line properly, with proper padding and name
# Usage: _FormatOut(TYPE,contents);
sub _FormatOut
{
	my $name = shift;
	my $origContents = shift;
	# If origContents isn't defined then just return an empty entry
	if(not defined($origContents))
	{
		return($name.' ""');
	}
	my $contents;
	my $contlines = 0;
	# Split on each newline in the string
	foreach my $part (split(/\\n/,$origContents))
	{
		$contents .= '"'.$part."\\n\"\n";
		$contlines++;
	}
	# If contents isn't set the set it now
	if(not $contents)
	{
		$contents = '"'.$origContents.'"';
		$contents .= "\n";
	}
	else
	{
		# If there were more than one line then the intial string should be ""
		if ($contlines > 1)
		{
			$contents = '""'."\n".$contents;
		}
		if(not $origContents =~ /\\n$/)
		{
			$contents =~ s/\\n"\n$/"\n/;
		}
	}
	return($name.' '.$contents);
}

# Purpose: Write a formatted po-file
# Usage: obj->_WriteFile(filename);
sub _WriteFile
{
	my $this = shift;
	my $filename = shift;
	if(not $filename)
	{
		carp("No file to write supplied");
		return;
	}

	# Change X-Generator if present
	$this->{PoFile}{1}{'msgstr'} =~ s/X-Generator: (\\n|(?:.(?!\\n))+.\\n)/X-Generator: MagicPO $VERSION\\n/;

	if ($this->{LastTranslator})
	{
		# Same with Last-Translator
		$this->{PoFile}{1}{'msgstr'} =~ s/Last-Translator: (\\n|(?:.(?!\\n))+.?\\n)/Last-Translator: MagicPO $VERSION (automated)\\n/;
	}
	# Now write it
	open(my $out,'>',$filename) or return $this->_err("Failed to open '$filename' for writing: $!");
	my $first = true;
	foreach my $ID(sort {$a <=> $b} keys(%{$this->{PoFile}}))
	{
		# Progress callback
		if (defined $this->{progressionCallback})
		{
			$this->{progressionCallback}->();
		}
		# If there's a raw data present and it's not the first ID then use that
		if (not $ENV{MAGICPO_P_IGNORERAW} and not $this->{dirty}{$ID} and not $first and defined($this->{PoFile}{$ID}{'magicpo-raw'}))
		{
			# First output a newline
			#print $out "\n";
			# If there's raw comments, output those first
			if ($this->{PoFile}{$ID}{'magicpo-rawcomments'})
			{
				print $out $this->{PoFile}{$ID}{'magicpo-rawcomments'};
				print $out "\n";
			}
			# Output the raw data
			print $out $this->{PoFile}{$ID}{'magicpo-raw'};
			# Move to the next one
			next;
		}
		# Delete keys that are only useful in raw-output mode
		delete($this->{PoFile}{$ID}{'magicpo-raw'});
		delete($this->{PoFile}{$ID}{'magicpo-rawcomments'});

		my $OutBuffer;
		if(not $first)
		{
			$OutBuffer .= "\n";
		}
		$first = false;
		# First output comments
		if ($this->{PoFile}{$ID}{'magicpo-comments'})
		{
			$OutBuffer .= $this->{PoFile}{$ID}{'magicpo-comments'}."\n";
			delete($this->{PoFile}{$ID}{'magicpo-comments'});
		}
		# Then statusflags
		if ($this->{PoFile}{$ID}{'magicpo-statusflags'})
		{
			my $flags = '#';
			# Always do fuzzy first if present
			if ($this->{PoFile}{$ID}{'magicpo-statusflags'}{'fuzzy'})
			{
				$flags .= ', fuzzy';
				delete($this->{PoFile}{$ID}{'magicpo-statusflags'}{'fuzzy'});
			}
			# Then do the rest
			foreach my $flag(keys(%{$this->{PoFile}{$ID}{'magicpo-statusflags'}}))
			{
				$flags .= ', '.$flag;
			}
			# Finally print them
			$OutBuffer .= $flags."\n";
			delete($this->{PoFile}{$ID}{'magicpo-statusflags'});
		}
		# Then prevtrans
		if ($this->{PoFile}{$ID}{'magicpo-prevtrans'})
		{
			$OutBuffer .= $this->{PoFile}{$ID}{'magicpo-prevtrans'}."\n";
			delete($this->{PoFile}{$ID}{'magicpo-prevtrans'});
		}

		# Then output any unknown stuff
		foreach my $key (sort keys(%{$this->{PoFile}{$ID}}))
		{
			next if $key =~ /^(msgid.*|msgctxt.*|msgstr.*|magicpo.*)$/;
			if ($key =~ /\s/)
			{
				$this->_perr("Found corrupt entry in output buffer ($key). Skipping.\n");
				delete($this->{PoFile}{$ID}{$key});
				next;
			}
			$OutBuffer .= _FormatOut($key,$this->{PoFile}{$ID}{$key});
			delete($this->{PoFile}{$ID}{$key});
		}
		# Keep track of the number of 'msgid' strings we write, there should only ever be
		# one written in one go. More means trouble.
		my $msgidCount = 0;
		# The max amounts of msgid allowed
		my $msgIdMax = 1;
		# We need to loop over msgctxt, msgstr and msgid, because there can be multiple variations
		foreach my $currstr (qw/msgctxt msgid msgstr/)
		{
			foreach my $key (sort keys(%{$this->{PoFile}{$ID}}))
			{
				next if not $key =~ /^$currstr/;
				if ($currstr eq 'msgid' and $key =~ /^msgid/)
				{
					if ($key =~ /^msgid_plural/)
					{
						$msgIdMax = 2;
					}
					$msgidCount++;
				}
				$OutBuffer .= _FormatOut($key,$this->{PoFile}{$ID}{$key});
				delete($this->{PoFile}{$ID}{$key});
			}
		}
		# If we wrote more than 1 msgid something is very wrong
		if ($msgidCount > $msgIdMax)
		{
			die("MagicPO::Parser: Fatal parser error: wrote $msgidCount 'msgid' strings in one go. There should only ever be one! Giving up.\n");
		}
		# Now check for leftover keys
		if(my @Keys = sort keys(%{$this->{PoFile}{$ID}}))
		{
			if (@Keys > 1)
			{
				my $Err;
				foreach(@Keys)
				{
					$Err .= ' '.$_;
				}
				$this->_perr("Parser warning: keys not deleted ($ID)! Bug. Keys: ".$Err."\n");
			}
			else
			{
				$this->_perr("Parser warning: key not deleted ($ID)! Bug. Key: $Keys[0]\n");
			}
		}
		# Write the output buffer if it's valid
		if (not $OutBuffer =~ /\n.*\n/)
		{
			$OutBuffer =~ s/\\n/\\\\n/;
			$OutBuffer =~ s/\n/\\n/;
			chomp($OutBuffer);
			$this->_perr("Found corrupt line in output buffer ($OutBuffer). Skipping.\n");
		}
		else
		{
			print $out $OutBuffer;
		}
	}
	# If we have some ending comments, then print those.
	if ($this->{ENDINGCOMMENTS})
	{
		$this->{ENDINGCOMMENTS} =~ s/^\n//g;
		print $out "\n";
		print $out $this->{ENDINGCOMMENTS};
	}
	# We're done, close up.
	close($out) or carp("Failed to close filehandle for file $filename ($!): The file may now be corrupt");
	return true;
}

# Purpose: Add an ID to the lookup table
# Usage: obj->_addToLookup(ID);
sub _addToLookup
{
	my $this = shift;
	my $ID = shift;
	my $isFromFile = shift;

	my $lookupString = $this->getLookup($ID);
	if (length($lookupString))
	{
		# Make sure that the lookup table doesn't already have a definition of this string,
		# if it does then it's a syntax error, we simply ignore the dupes in order to repair
		# the file.
		if($isFromFile and defined $this->{Lookup}{$lookupString})
		{
			# Ouch, duplicate definitions. This is a PO syntax-error
			$this->_perr("String ($lookupString) already defined earlier in the file. This is a syntax-error in the PO-file, ignoring this definition\n");
			# Delete what we have parsed so far and set the ReplaceLastID flag
			delete($this->{PoFile}{$ID});
			$this->{ReplaceLastID} = true;
		}
		else
		{
			# Add entry to lookup table
			$this->{Lookup}{$lookupString} = $ID;
		}
	}
}
1;
