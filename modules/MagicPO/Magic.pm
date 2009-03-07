#!/usr/bin/perl
# MagicPO::Magic
# Copyright (C) Eskild Hustvedt 2008
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

package MagicPO::Magic;
use strict;
use warnings;
use constant { 
	# These make prettier code
	true => 1, false => 0 
};
use Carp;
our $VERSION;
$VERSION = 0.4;

# Purpose: Create a new object
# Usage: $obj = MagicPO::DictLoader->new(MagicPO::DictLoader, progressionCallback, replaceFuzzy?, monitorThis?);
#	MagicPO::DictLoader is an instance of the MagicPO::DictLoader object
#		containing the dictionary to use
#	progressionCallback is a coderef to the function to call every time
#		something has progressed. Can be undef.
#	replaceFuzzy is a boolean
#	monitorThis is an int, will print information about what dictionary entry changed
#		that string
sub new
{
	my $this = shift;
	$this = {};
	$this->{dict} = shift;
	if (not $this->{dict})
	{
		croak('No dictionary supplied while creating a MagicPO::Magic object');
	}
	$this->{dictMax} = scalar @{$this->{dict}->{dict}};
	$this->{progressionCallback} = shift;
	$this->{replaceFuzzy} = shift;
	$this->{monitorNo} = shift;
	bless($this,'MagicPO::Magic');
	return $this;
}

# Purpose: Replace a single string
# Usage: newString = obj->replaceString(string,no?);
# 	No can be undef. Is the current string number.
sub replaceString
{
	my $this = shift;
	my $string = shift;
	my $stringNo = shift;
	my $rdict = $this->{dict};
	my $dirty = false;
	my $newString;

	foreach my $strPart (split(/\n/,$string))
	{
		next if $strPart =~ /^(<|\%)/;
		# Pad the string
		$strPart = ' '.$strPart.' ';
		# Prep exhaustive regexping on $string
		study $strPart;
		# Save the original string
		my $origString = $strPart;

		# Go through all possible priorities
		for my $i (reverse 0..$this->{dictMax})
		{
			# If the priority is unused, just skip it
			next if not defined $rdict->{dict}[$i];
			# Go through all possible replacements
			while(my ($from,$to) = each %{$rdict->{dict}[$i]})
			{
				# Make changes to the strPart as needed. $1 and $2 comes from the dictionary
				if($strPart =~ s/$from/$1$to$2/g)
				{
					# It has changed, study the new string
					study $strPart;
					# If it's not the same then perform additional tests
					if (not $origString eq $strPart)
					{
						if(defined $this->{monitorNo} and $this->{monitorNo} eq $stringNo)
						{
							print "Change to $stringNo: s/$from/$to/;\n";
						}
						# Mark it as dirty
						$dirty = true;
					}
				}
			}
		}
		# Remove padding
		$strPart =~ s/^\s//;
		$strPart =~ s/\s$//;
		# Append
		$newString .= $strPart;
		# We have progressed, let the callback know
		$this->_progressed();
	}
	# Remove added newlines
	if(not $newString)
	{
		$newString = $string;
	}
	else
	{
		$newString =~ s/\n//g;
	}
	# If the caller wants more than one return value, return the new
	# string and the dirty status
	if(wantarray())
	{
		return ($newString,$dirty);
	}
	# If not, just return the new string
	else
	{
		return($newString);
	}
}

# Purpose: Replace everything in a file (file being a MagicPO::Parser object)
# Usage: dirty = obj->replaceFile(object, olderobj);
#	olderobj can be undef, if it is not then it will only process strings
#	that are either not present or fuzzy in the olderobj
# Returns true if something was replaced, false if nothing was replaced.
sub replaceFile
{
	my $this = shift;
	my $file = shift;
	my $olderfile = shift;
	my $dirty = false;

	my $processCurrent = true;
	# Process each msgstr
	foreach my $key(keys(%{$file->{PoFile}}))
	{
		next if $key == 1;
		my $IsFuzzy = false;
		# Only try to replace if the string actually exists
		foreach my $entry (keys(%{$file->{PoFile}{$key}}))
		{
			if ($olderfile)
			{
				if ($entry =~ /^msgid/)
				{
					my $lookup = $file->getLookup($key);
					$processCurrent = $this->_isStringPresentAndEmpty($olderfile,$lookup);
					next;
				}
				next if not $processCurrent;
			}
			# Only process msgstr and variations
			next if not $entry =~ /^msgstr/;
			# If the entry is defined and nonempty then go on
			if(defined($file->{PoFile}{$key}{$entry}) and $file->{PoFile}{$key}{$entry})
			{
				# Get the replaced string
				my ($newstring,$dirtyString) = $this->replaceString($file->{PoFile}{$key}{$entry},$key);
				# If the string is identical to the old one then leave it alone
				if($dirtyString)
				{
					# It wasn't identical, so set the new one
					$file->{PoFile}{$key}{$entry} = $newstring;
					# Mark file as dirty, means we need to write it
					$dirty = true;
					# Mark it as dirty
					$file->markdirty($key);
				}
			}
		}
	}
	return($dirty);
}

# Purpose: Check if STRING is present in OBJECT and empty.
# Usage: this->_isStringPresentAndEmpty(OBJECT,STRING);
#  Presence might also depend upon the replaceFuzzy option
sub _isStringPresentAndEmpty
{
	my $this = shift;
	my $object = shift;
	my $string = shift;
	my $lookup = $object->{Lookup}->{$string};
	my $ret = false;
	if (defined($lookup))
	{
		if ($object->{PoFile}{$lookup}{'magicpo-statusflags'}{'fuzzy'})
		{
			if ($this->{replaceFuzzy})
			{
				return true;
			}
			else
			{
				return false;
			}
		}
		foreach my $str (keys %{$object->{PoFile}{$lookup}})
		{
			next if not $str =~ /^msgstr/;
			if ($object->{PoFile}{$lookup}{$str} eq '')
			{
				$ret = true;
			}
			else
			{
				$ret = false;
			}
		}
	}
	return $ret;
}

# Purpose: Internal progression indicator. Calls progression callback if
# 	available
# Usage: this->_progressed();
sub _progressed
{
	my $this = shift;
	if(not $this->{progressionCallback})
	{
		return true;
	}
	$this->{progressionCallback}->();
	return true;
}

1;
