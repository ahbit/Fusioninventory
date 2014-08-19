package HTTP::Proxy::FilterStack;

# Here's a description of the class internals
# - filters: the list of (sub, filter) pairs that match the message,
#            and through which it must go
# - current: the actual list of filters, which is computed during
#            the first call to filter()
# - buffers: the buffers associated with each (selected) filter
# - body   : true if it's a HTTP::Proxy::BodyFilter stack

use strict;
use Carp;

# new( $isbody )
# $isbody is true only for response-body filters stack
sub new {
    my $class = shift;
    my $self  = {
        body => shift || 0,
        filters => [],
        buffers => [],
        current => undef,
    };
    $self->{type} = $self->{body} ? "HTTP::Proxy::BodyFilter"
                                  : "HTTP::Proxy::HeaderFilter";
    return bless $self, $class;
}

#
# insert( $index, [ $matchsub, $filter ], ...)
#
sub insert {
    my ( $self, $idx ) = ( shift, shift );
    $_->[1]->isa( $self->{type} ) or croak("$_ is not a $self->{type}") for @_;
    splice @{ $self->{filters} }, $idx, 0, @_;
}

#
# remove( $index )
#
sub remove {
    my ( $self, $idx ) = @_;
    splice @{ $self->{filters} }, $idx, 1;
}

# 
# push( [ $matchsub, $filter ], ... )
# 
sub push {
    my $self = shift;
    $_->[1]->isa( $self->{type} ) or croak("$_ is not a $self->{type}") for @_;
    push @{ $self->{filters} }, @_;
}

sub all    { return @{ $_[0]->{filters} }; }
sub will_modify { return $_[0]->{will_modify}; }

#
# select the filters that will be used on the message
#
sub select_filters {
    my ($self, $message ) = @_;

    # first time we're called this round
    if ( not defined $self->{current} ) {

        # select the filters that match
        $self->{current} =
          [ map { $_->[1] } grep { $_->[0]->() } @{ $self->{filters} } ];

        # create the buffers
        if ( $self->{body} ) {
            $self->{buffers} = [ ( "" ) x @{ $self->{current} } ];
            $self->{buffers} = [ \( @{ $self->{buffers} } ) ];
        }

        # start the filter if needed (and pass the message)
        for ( @{ $self->{current} } ) {
            if    ( $_->can('begin') ) { $_->begin( $message ); }
            elsif ( $_->can('start') ) {
                $_->proxy->log( HTTP::Proxy::ERROR(), "DEPRECATION", "The start() filter method is *deprecated* and disappeared in 0.15!\nUse begin() in your filters instead!" );
            }
        }

        # compute the "will_modify" value
        $self->{will_modify} = $self->{body}
            ? grep { $_->will_modify() } @{ $self->{current} }
            : 0;
    }
}

#
# the actual filtering is done here
#
sub filter {
    my $self = shift;

    # pass the body data through the filter
    if ( $self->{body} ) {
        my $i = 0;
        my ( $data, $message, $protocol ) = @_;
        for ( @{ $self->{current} } ) {
            $$data = ${ $self->{buffers}[$i] } . $$data;
            ${ $self->{buffers}[ $i ] } = "";
            $_->filter( $data, $message, $protocol, $self->{buffers}[ $i++ ] );
        }
    }
    else {
        $_->filter(@_) for @{ $self->{current} };
        $self->eod;
    }
}

#
# filter what remains in the buffers
#
sub filter_last {
    my $self = shift;
    return unless $self->{body};    # sanity check

    my $i = 0;
    my ( $data, $message, $protocol ) = @_;
    for ( @{ $self->{current} } ) {
        $$data = ${ $self->{buffers}[ $i ] } . $$data;
        ${ $self->{buffers}[ $i++ ] } = "";
        $_->filter( $data, $message, $protocol, undef );
    }

    # call the cleanup routine if needed
    for ( @{ $self->{current} } ) { $_->end if $_->can('end'); }
    
    # clean up the mess for next time
    $self->eod;
}

#
# END OF DATA cleanup method
#
sub eod {
    $_[0]->{buffers} = [];
    $_[0]->{current} = undef;
}

1;

__END__

=head1 NAME

HTTP::Proxy::FilterStack - A class to manage filter stacks

=head1 DESCRIPTION

This class is used internally by L<HTTP::Proxy> to manage its
four filter stacks.

From the point of view of L<HTTP::Proxy::FilterStack>, a filter is
actually a (C<matchsub>, C<filterobj>) pair. The match subroutine
(generated by L<HTTP::Proxy>'s C<push_filter()> method) is run
against the current L<HTTP::Message> object to find out which filters
must be kept in the stack when handling this message.

The filter stack maintains a set of buffers where the filters can
store data. This data is appended at the beginning of the next
chunk of data, until all the data has been sent.

=head1 METHODS

The class provides the following methods:

=over 4

=item new( $isbody )

Create a new instance of L<HTTP::Proxy::FilterStack>. If C<$isbody>
is true, then the stack will manage body filters (subclasses of
L<HTTP::Proxy::BodyFilter>).

=item select_filters( $message )

C<$message> is the current L<HTTP::Message> handled by the proxy.
It is used (with the help of each filter's match subroutine)
to select the subset of filters that will be applied on the
given message.

=item filter( @args )

This method calls all the currently selected filters in turn,
with the appropriate arguments.

=item filter_last()

This method calls all the currently selected filters in turn,
to filter the data remaining in the buffers in a single pass.

=item will_modify()

Return a boolean value indicating if the list of selected filters in
the stack will modify the body content. The value is computed from the
result of calling C<will_modify()> on all selected filters.

=item all()

Return a list of all filters in the stack.

=item eod()

Used for END OF DATA bookkeeping.

=item push()

Push the given C<[ match, filterobj ]> pairs at the top of the stack.

=item insert( $idx, @pairs )

Insert the given C<[ match, filterobj ]> pairs at position C<$idx>
in the stack.

=item remove( $idx )

Remove the C<[ match, filterobj ]> pair at position C<$idx> in the stack.

=back

=head1 AUTHOR

Philippe "BooK" Bruhat, E<lt>book@cpan.orgE<gt>.

=head1 COPYRIGHT

Copyright 2002-2013, Philippe Bruhat.

=head1 LICENSE

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

