#!/usr/bin/perl
# MagicPO::DictLoader
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

package MagicPO::DictLoader;
use strict;
use warnings;
use constant { 
	# These make prettier code
	true => 1, false => 0 
};
use Carp;
our $VERSION;
$VERSION = 0.4;
our $RCSREV;
$RCSREV = '$Id$';

# The string used to indicate that something is not a word.
# Note: _ is considered a part of a word
# getAllEscaped takes care of escaping it and the replacement functions adds
# ([])
my $notwordString = _getAllEscaped('s,.-:;()!?[]"\'/<>«»©');
my $notwordStringExcept = '|\s_|\\\\n|\\\\t';

# Purpose: Create a new object
# Usage: $obj = MagicPO::DictLoader->new(dictionary, progressionCallback);
# 	file is the dictionary file to read
#	progressionCallback is a coderef to the function to call every time
#		something has progressed. Can be undef.
sub new
{
	my $this = shift;
	my $file = shift;
	$this = {};
	$this->{file} = $file;
	$this->{progressionCallback} = shift;
	$this->{lineno} = 0;
	$this->{phrases} = 0;
	$this->{dict} = [];
	bless($this,'MagicPO::DictLoader');
	if($this->_loadDict())
	{
		return($this);
	}
	else
	{
		return false;
	}
}

# Purpose: Main dictionary loader
# Usage: this->_loadDict();
sub _loadDict 
{
	my $this = shift;
	# Ensure it's there
	if(not -e $this->{file})
	{
		carp("$this->{file}: does not exist");
		return;
	}
	elsif (not -r $this->{file})
	{
		carp("$this->{file}: is not readable (check permissions)");
		return;
	}
	elsif (-d $this->{file})
	{
		carp("$this->{file}: is a directory");
		return;
	}
	# Characters to escape in the "from" part
	my $escregex = _getAllEscaped('!@$%&(){}^|');
	# Open the file for reading
	open(my $FILE, '<', $this->{file}) or return $this->_err("Unable to open the file $this->{file}: $!");
	# Read every line in the file
	local $/ = "\n";
	while(my $line = <$FILE>)
	{
		# Bump line number
		$this->{lineno}++;
		# The priority of this entry
		my $priority = 0;
		# Used for temporarily saving priority values from _replaceTag
		my($pri1,$pri3);
		# Skip comments
		next if $line =~ /^\s*#/;
		# Skip empty lines
		next if not $line =~ /\S/;
		# We need a =
		if(not $line =~ /=/)
		{
			$this->_perr('Doesn\'t look like a dictionary entry');
			next;
		}
		# Remove newlines
		chomp $line;
		# Grab the from part and sanitise it by removing whitespace
		(my $from = $line) =~ s/^\s*([^=]+)\s*\=.*$/$1/;
		$from =~ s/^\s*//;
		$from =~ s/\s*$//;
		# Grab the to part
		(my $to = $line) =~ s/^\s*[^=]+\s*\=\s?(.+)$/$1/;
		# If we didn't extract something then the line is malformed
		if ((($to eq $line) or ($from eq $line)) or (not length($from) or not length($to)))
		{
			$this->_perr('Unable to parse');
			next;
		}

		# The regex used to extract 'from' parts
		my $fromextractor = '^(\*?)(.*?)(\*?)$';
		# Get the first 'from' part
		(my $from_pt1 = $from) =~ s/$fromextractor/$1/;
		# Second
		(my $from_pt2 = $from) =~ s/$fromextractor/$2/;
		# Third
		(my $from_pt3 = $from) =~ s/$fromextractor/$3/;
		# Ensure that at least from_pt2 exists
		if(not length($from_pt2) or not $from_pt2 =~ /\S/)
		{
			$this->_perr('From part is malformed');
			next;
		}
		# Convert MagicPO characters to regular expressions
		($from_pt1, $pri1) = $this->_replaceTag($from_pt1);
		($from_pt3, $pri3) = $this->_replaceTag($from_pt3);
		# Escape special characters in 'from'
		$from_pt2 =~ s/([$escregex])/\\$1/g;
		# Get final priority
		$priority = $pri1+$pri3+length($from_pt2);
		# Bump the number of phrases
		$this->{phrases}++;
		# Finally add it to the list. We add two versions, one lowercase
		# and one uppercase version.
		$this->{dict}[$priority]{$from_pt1.ucfirst($from_pt2).$from_pt3} = ucfirst($to);
		$this->{dict}[$priority]{$from_pt1.$from_pt2.$from_pt3} = $to;
		# Call progression callback if needed
		$this->_progressed();
	}
	close $FILE or carp("Failed to close filehandle ($FILE) for dictionary file: $!\n");
	return true;
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

# Purpose: Replace dictionary tags with regex characters
# Usage: ($string, $priority) = $this->_replaceTag($Scalar);
sub _replaceTag {
	my $this = shift;
	my $tag = shift;
	if ($tag eq '*')
	{
		return ('(.)', 0);	# Can have any character. Priority value 0 (lowest).
	}
	elsif($tag eq '+')
	{
		return ('(\w)', 4); # Must be an alphanumeric. Priority value 4 (middle).
	}
	# Must not be an alphanumeric. Priority value 10 (highest).
	return ('(['.$notwordString.']'.$notwordStringExcept.')', 10);
}

# Purpose: Get a properly escaped string
# Usage: _getAllEscaped(string);
sub _getAllEscaped
{
	my $string = shift;
	my $newstring;
	foreach(split(//,$string))
	{
		$newstring .= '\\'.$_;
	}
	return($newstring);
}

# Purpose: Write info about parser errors or warnings
# Usage: obj->_perr(MSG);
sub _perr
{
	my $this = shift;
	my $message = shift;
	if ($this->{lineno})
	{
			$this->_err($this->{file}.'      line '.$this->{lineno}.': '.$message);
	}
	else
	{
		$this->_err($this->{file}.'           : '.$message);
	}
	if (defined($ENV{MAGICPO_D_CALLT}) and $ENV{MAGICPO_D_CALLT})
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

1;
