
use strict;
use Data::Dumper;
#use List::Util qw(reduce);
use JSON;

package DataSource;

sub new {
	my $class = shift;
	my $this = { ( @_ ) };
	bless $this, $class;
	$this->setSource() if $this->{symbol};	
	#print Data::Dumper->Dump( [$this], ["DataSource->new"] );
	return $this;
}

sub source { 
	my $fileName = $_[0]->{path} . "\\" . $_[0]->{source};
	return $fileName;
}
sub symbol {  return $_[0]->{symbol}; }

sub setSymbol {
my ($this, $sym) = @_;
	$this->{symbol} = $sym;
	$this->setSource();	
}

sub setSource {
my ($this) = @_;
	die ("setSource, need symbol\n"), return unless $this->{symbol};
	$this->{source} = $this->bestSource(); 
	# print "out setSource ", $this->source(),"\n";
	return $this->{source};
}

sub bestSource {
my ($this ) = @_;
	my $issue = $this->{symbol};
	opendir my $hdir, $this->{path};
	$issue =~ s/^\$/^\\\$/;		# escape leading $ (e.g. $SPX -> \$SPY), generalize into a quote method as needed
	print "$issue\n";
	my @choices = sort grep { /^$issue .*\.csv$/ } readdir $hdir;
	closedir $hdir;
	#print join( "\n", @choices);
	#return wantarray() ? \@choices : $choices[-1];
	return $choices[-1];
}

sub load {
my ($this, $symbol) = @_;
	
	$this->setSymbol($symbol) if $this->{symbol} ne  $symbol;
	die "No symbol set in load\n" unless $this->{symbol};
	
	my $source = $this->source();
	die "source $source not found for ", $this->symbol(), "\n"  unless -f $source;

	open IN, $source;
	my $hdr = <IN>;
	chomp $hdr;
	$hdr =~ s/\s//g;
	$hdr =~ s/Vol\*/Vol/;
	my @fields = split ',',$hdr;
	$this->{header} = \@fields;

	my %headerIndex;
	$this->{headerIndex} = \%headerIndex;
	foreach my $index ( 0 .. scalar(@fields)-1 )
	{
		$headerIndex{$fields[$index]} = $index;
	}

	my @series;
	$this->{series} = \@series;

	while ( <IN> )
	{
		chomp;
		my @vals = split ',';
		push @series, \@vals;
	}
	close IN;

	$this->normalizeDate();
	$this->setReturn();
	return \@series;
}

sub normalizeDate {
my ( $this, $data ) = @_;
	my $index = $this->{headerIndex};
	die "Header not found\n" unless $index;
	return if $index->{NormDate};

	die "Date field not found\n" unless defined $index->{Date};
	my $dateIndx = $index->{Date};

	my $series = $this->{series};
	my $size = scalar( @{$series->[0]} );
	$index->{NormDate} = $size;

	foreach my $entry ( @$series )
	{
		my $date = $entry->[$dateIndx];
		my @components = split '\/', $date;
		my $normDate = $components[2] . $components[0] . $components[1];
		push @$entry,$normDate;
	}	
}

sub setReturn {
my ( $this ) = @_;

	my $hdr = $this->{headerIndex};
	die "Header not found\n" unless $hdr;
	return if $hdr->{Return};

	die "Close field not found\n" unless defined $hdr->{Close};
	my $closeIndex = $hdr->{Close};

	my $series = $this->{series};
	my $size = scalar( @{$series->[0]} );
	$hdr->{Return} = $size;

	my $enteries = scalar( @$series );
	foreach my $index ( 0 .. $enteries-2 )
	{
		my $curEntry = $series->[$index];
		my $nextEntry = $series->[$index+1];
		my $close = $curEntry->[$closeIndex];
		my $prev = $nextEntry->[$closeIndex];
		my $chg = $close-$prev;
		my $return = $chg/$prev;
		push @$curEntry,$return;
	}	
}

# options: ascending (bool) if data series is loaded oldest first
sub getSeries {
my ($this, $value, %options ) = @_;
	my @series;
	my $hdr = $this->{headerIndex};
	die "Header not found\n" unless $hdr;

	my $dateIndx = $hdr->{Date};
	die "$value field not found\n" unless defined $hdr->{$value};

	my $valIndx = $hdr->{$value};
	my $orig = $this->{series};
	foreach my $entry ( @$orig )
	{
		unshift @series, $entry->[$valIndx];
	}
	@series = reverse @series if $options{ascending};
	shift @series if $value eq 'Return';
	return \@series;
}

1;

package MarketData;

my $defaults = {
	path => "\\Users\\lstee\\Documents\\Interactive Data\\",
};

sub new {
	my $class = shift;
	my $this = { ( %$defaults, @_ ) };
	bless $this, $class;
	#print Data::Dumper->Dump( [$this] );
	return $this;
};

sub symbol { my ($this) = @_; return $this->{symbol}; }
sub source { my ($this) = @_; return $this->{data}->{source}; }


sub loadData {
my ($this) = @_;
	$this->{data} = DataSource->new( 'path' => $this->{path} );
	#print Data::Dumper->Dump( [$this->{data}] );
	$this->{data}->load( $this->symbol() );
	#print Data::Dumper->Dump( [$this->{data}] );
}

sub setSymbol {
my ($this, $sym) = @_;
	#print "In setSymbol\n";
	$this->{symbol} = $sym;
}

sub getSeries {
my ($this, $value ) = @_;
	my $dataIsAscending = 0;	# tic srv export (default) is always in decending order
	return $this->{data}->getSeries( $value, 'ascending' => $dataIsAscending );
}


# ************* classless support methods, though can be called as class methods ... ************
# options: 
# 	back_window - return mean of last 'back_window' elements
# 	ignore_leadingnulls - skip all leading 0/na values (for moving avg)
# 
sub mean {
	shift @_ if ref $_[0] eq 'MarketData';
	my ($series, %options) = @_;
	print Data::Dumper->Dump( [%options], ['Mean:options' ] ) if $options{ verbose };

	my $startIndex = 0;
	my $count = @$series;
	print "initial size $count\n" if $options{verbose};


	my $bw = $options{back_window};
	if ( $bw && $bw < $count )
	{
		$startIndex = $count-$bw;
		print "back window: $bw, startIndex $startIndex\n" if $options{verbose};
	}

	while ( $options{ignore_leadingnulls} )
	{
		++$startIndex,  next unless $series->[$startIndex];
		last;
	}
	print "starting at $startIndex\n" if $options{verbose};


	my $tot = 0;
	my $seen = 0;
	foreach my $index ( $startIndex .. (scalar @{$series})-1 )
	{
		my $next = $series->[$index];
		$tot += $next;
		++$seen;
		print "index $index, val $next, tot $tot\n" if $options{verbose};
	}

	my $mean = $seen ? $tot/$seen : 0;
	print "mean $mean\n" if $options{verbose};
	$mean;
}

sub meanDeviation {
	shift @_ if ref $_[0] eq 'MarketData';
	my ( $s, $mean ) = @_;
	
	$mean = mean($s) unless defined $mean;
	my @result = map { $_ - $mean } @$s;
	\@result;
}

# movingAverage
# options: 	
# 	decimals - force return value precision, does not affect accumulator precision
# 	count - set max return count, dev/debug (mostly)
# 	flavor - (pending) moving average type, default sma
# 	verbose - display internal state, dev/debug
sub movingAverage {
	shift @_ if ref $_[0] eq 'MarketData';
	my ($window, $values, %options ) = @_;

	print Data::Dumper->Dump( [%options] ) if $options{ verbose };

	my $error = 0;

	my $count = scalar @$values;
	$count = $options{count} if $options{count} && ($options{count} < $count);

	$error = -1 if $count == 0;
	$error = -2 if $window > $count;
	$error = -3 if $window < 2;
	return (wantarray ? (undef, $error) : undef) unless $error == 0;

	print "Moving Average: window $window, series size: $count\n" if $options{verbose};

	my @output;
	my $avg = 0;
	my $decimals = $options{decimals};
	my $leadingVal = 0;
	foreach my $index ( 0 .. $count-1 )
	{
		my $leading = $values->[$index];
		my $toAdd = $leading / $window;
		$avg += $toAdd;
		my $trailing = ($index >= $window) ? $values->[$index-$window] : $leadingVal;
		my $toremove = $trailing / $window;
		$avg -= $toremove;
		my $formatted = (defined $decimals) ? sprintf( "%.*f", $decimals, $avg ) : $avg;
		push @output, ($index < $window) ? 0 : $formatted;
		print ( "Index $index, new $leading, adds $toAdd, old $trailing, removes $toremove, avg $avg, movavg $output[-1]\n" ) if $options{verbose};
	}
	return  wantarray ? (\@output,$error) : \@output;
}

sub outputDelimited {
	shift @_ if ref $_[0] eq 'MarketData';
	my ($dest, $header, $series, %options ) = @_;
	print Data::Dumper->Dump( [%options] );

	my $outHandle = undef;
	open $outHandle, ">$dest" if length $dest;

	my $delimiter = $options{delimiter} || ',';
	print $outHandle join( $delimiter, @$header ),"\n" if $outHandle;
	print STDOUT join( $delimiter, @$header ),"\n" if $options{stdout};
	my $maxSize = 0;
	foreach my $s (@$series) { $maxSize = scalar(@$s) if $maxSize < scalar(@$s); }
	foreach my $index ( 0 .. $maxSize-1 )
	{
		my @vals = map { defined $_->[$index] ? $_->[$index] : 'undef' } @$series;
		print $outHandle join( $delimiter, @vals ),"\n" if $outHandle;
		print STDOUT join( $delimiter, @vals ),"\n" if $options{stdout};
	}
}

# doesn't particularly belong here but a common use case
# returns hashref of contents of $defaults hashref overloaded by json from file $cfg
sub loadConfig {
	shift @_ if ref $_[0] eq 'MarketData';
	my ($cfg, $defaults) = @_;
	open IN, $cfg;
	my @val = <IN>;
	my $val = join "", @val;
	#print Data::Dumper->Dump( [$val] );
	my $loaded = ::decode_json( $val );
	#print Data::Dumper->Dump( [$loaded] );
	my %result = (%$defaults, %$loaded);
	#print Data::Dumper->Dump( [%result] );
	return \%result;
}

1;

__DATA__
