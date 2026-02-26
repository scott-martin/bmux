#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use JSON::PP;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Bmux::Input;
use Bmux::CDP;

# Coordinate-based click is the default. Target.activateTarget brings the
# browser window to foreground (browser calls SetForegroundWindow itself).
# JS .click() is a fallback via --js flag.

# --- Command builders ---

# activateTarget — bring browser to foreground
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_activate_target($cdp, 'ABC123');
    my $msg = decode_json($json);

    is($msg->{method}, 'Target.activateTarget', 'activateTarget method');
    is($msg->{params}{targetId}, 'ABC123', 'activateTarget targetId');
}

# mouseMoved — hover before click
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_mouse_moved($cdp, 200, 300);
    my $msg = decode_json($json);

    is($msg->{method}, 'Input.dispatchMouseEvent', 'mouseMoved method');
    is($msg->{params}{type}, 'mouseMoved', 'mouseMoved type');
    is($msg->{params}{x}, 200, 'mouseMoved x');
    is($msg->{params}{y}, 300, 'mouseMoved y');
}

# Low-level building blocks:
# Step 1: querySelector to find the node
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_query_selector($cdp, 1, 'button#login');
    my $msg = decode_json($json);

    is($msg->{method}, 'DOM.querySelector', 'click step1: querySelector');
    is($msg->{params}{selector}, 'button#login', 'click step1: selector');
}

# Step 2: getBoxModel to find click coordinates
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_get_box_model($cdp, 42);
    my $msg = decode_json($json);

    is($msg->{method}, 'DOM.getBoxModel', 'click step2: getBoxModel');
    is($msg->{params}{nodeId}, 42, 'click step2: nodeId');
}

# Step 3: compute click point from box model content quad
{
    # content quad: [x1,y1, x2,y2, x3,y3, x4,y4] — corners of the box
    my @quad = (100, 200, 300, 200, 300, 250, 100, 250);
    my ($x, $y) = Bmux::Input::center_of_quad(@quad);

    is($x, 200, 'center x');
    is($y, 225, 'center y');
}

# Step 4: mousePressed event
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_mouse_pressed($cdp, 150, 225);
    my $msg = decode_json($json);

    is($msg->{method}, 'Input.dispatchMouseEvent', 'mousePressed method');
    is($msg->{params}{type}, 'mousePressed', 'mousePressed type');
    is($msg->{params}{x}, 150, 'mousePressed x');
    is($msg->{params}{y}, 225, 'mousePressed y');
    is($msg->{params}{button}, 'left', 'mousePressed button');
    is($msg->{params}{clickCount}, 1, 'mousePressed clickCount');
}

# Step 5: mouseReleased event
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_mouse_released($cdp, 150, 225);
    my $msg = decode_json($json);

    is($msg->{method}, 'Input.dispatchMouseEvent', 'mouseReleased method');
    is($msg->{params}{type}, 'mouseReleased', 'mouseReleased type');
}

# focus — needed before fill/type
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_focus($cdp, 42);
    my $msg = decode_json($json);

    is($msg->{method}, 'DOM.focus', 'focus method');
    is($msg->{params}{nodeId}, 42, 'focus nodeId');
}

# fill — set value via JS on the node
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_set_value($cdp, 42, 'scott@omatic.com');
    my $msg = decode_json($json);

    is($msg->{method}, 'Runtime.evaluate', 'set_value uses evaluate');
    like($msg->{params}{expression}, qr/scott\@omatic\.com/, 'set_value contains value');
}

# type — individual key events
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_key_event($cdp, 'keyDown', 'a');
    my $msg = decode_json($json);

    is($msg->{method}, 'Input.dispatchKeyEvent', 'keyDown method');
    is($msg->{params}{type}, 'keyDown', 'keyDown type');
    is($msg->{params}{text}, 'a', 'keyDown text');
}

{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_key_event($cdp, 'keyUp', 'a');
    my $msg = decode_json($json);

    is($msg->{params}{type}, 'keyUp', 'keyUp type');
}

# wait — builds querySelector (polling done at higher level)
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_query_selector($cdp, 1, '.dashboard');
    my $msg = decode_json($json);

    is($msg->{method}, 'DOM.querySelector', 'wait uses querySelector');
    is($msg->{params}{selector}, '.dashboard', 'wait selector');
}

# click via JS — resolves node then calls .click()
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_js_click($cdp, 'obj-123');
    my $msg = decode_json($json);

    is($msg->{method}, 'Runtime.callFunctionOn', 'js_click uses callFunctionOn');
    is($msg->{params}{objectId}, 'obj-123', 'js_click objectId');
    like($msg->{params}{functionDeclaration}, qr/\.click\(\)/, 'js_click calls .click()');
}

# resolve node to JS object
{
    my $cdp = Bmux::CDP->new();
    my ($id, $json) = Bmux::Input::cmd_resolve_node($cdp, 42);
    my $msg = decode_json($json);

    is($msg->{method}, 'DOM.resolveNode', 'resolve node method');
    is($msg->{params}{nodeId}, 42, 'resolve node nodeId');
}

# --- Integration: run_click with mock CDP ---
# Verify that run_click calls the right CDP commands in the right order.
{
    package MockCDP;
    sub new { bless { calls => [], target_id => 'TAB-42' }, shift }
    sub send_command {
        my ($self, $method, $params) = @_;
        push @{$self->{calls}}, { method => $method, params => $params };
        # Return values needed by run_click's control flow:
        if ($method eq 'DOM.getDocument') {
            return { root => { nodeId => 1 } };
        }
        if ($method eq 'DOM.querySelector') {
            return { nodeId => 99 };
        }
        if ($method eq 'DOM.resolveNode') {
            return { object => { objectId => 'obj-99' } };
        }
        if ($method eq 'DOM.getBoxModel') {
            # 100x50 box at (100,200)
            return { model => { content => [100,200, 200,200, 200,250, 100,250] } };
        }
        return {};
    }

    package main;

    my $mock = MockCDP->new();
    # Suppress STDOUT from run_click
    my $out;
    open my $capture, '>', \$out;
    my $old = select $capture;

    Bmux::Input::run_click($mock, { object => 'button.login' });

    select $old;
    close $capture;

    my @calls = @{$mock->{calls}};
    my @methods = map { $_->{method} } @calls;

    # Verify the sequence: getDocument → querySelector → activate →
    # resolveNode → scrollIntoView → getBoxModel → 3x dispatchMouseEvent
    is($methods[0], 'DOM.getDocument', 'run_click: gets document');
    is($methods[1], 'DOM.querySelector', 'run_click: finds element');
    is($calls[1]{params}{selector}, 'button.login', 'run_click: correct selector');
    is($methods[2], 'Target.activateTarget', 'run_click: activates target');
    is($calls[2]{params}{targetId}, 'TAB-42', 'run_click: correct target id');
    is($methods[3], 'DOM.resolveNode', 'run_click: resolves node');
    is($methods[4], 'Runtime.callFunctionOn', 'run_click: scrollIntoView');
    like($calls[4]{params}{functionDeclaration}, qr/scrollIntoView/,
         'run_click: scrollIntoViewIfNeeded');
    is($methods[5], 'DOM.getBoxModel', 'run_click: gets box model');

    # The three mouse events
    is($methods[6], 'Input.dispatchMouseEvent', 'run_click: mouseMoved');
    is($calls[6]{params}{type}, 'mouseMoved', 'run_click: mouseMoved type');
    is($methods[7], 'Input.dispatchMouseEvent', 'run_click: mousePressed');
    is($calls[7]{params}{type}, 'mousePressed', 'run_click: mousePressed type');
    is($methods[8], 'Input.dispatchMouseEvent', 'run_click: mouseReleased');
    is($calls[8]{params}{type}, 'mouseReleased', 'run_click: mouseReleased type');

    # Verify coordinates are center of the box (150, 225)
    is($calls[6]{params}{x}, 150, 'run_click: click x = center');
    is($calls[6]{params}{y}, 225, 'run_click: click y = center');
    is($calls[7]{params}{x}, 150, 'run_click: press x = center');
    is($calls[7]{params}{y}, 225, 'run_click: press y = center');

    like($out, qr/Clicked button\.login at \(150, 225\)/, 'run_click: output message');
}

# --- Integration: run_click --js flag falls back to JS click ---
{
    package MockCDP2;
    sub new { bless { calls => [], target_id => 'TAB-42' }, shift }
    sub send_command {
        my ($self, $method, $params) = @_;
        push @{$self->{calls}}, { method => $method, params => $params };
        if ($method eq 'DOM.getDocument') {
            return { root => { nodeId => 1 } };
        }
        if ($method eq 'DOM.querySelector') {
            return { nodeId => 99 };
        }
        if ($method eq 'DOM.resolveNode') {
            return { object => { objectId => 'obj-99' } };
        }
        return {};
    }

    package main;

    my $mock = MockCDP2->new();
    my $out;
    open my $capture, '>', \$out;
    my $old = select $capture;

    Bmux::Input::run_click($mock, {
        object    => 'a.link',
        modifiers => { '--js' => 1 },
    });

    select $old;
    close $capture;

    my @methods = map { $_->{method} } @{$mock->{calls}};

    # Should NOT have Target.activateTarget or dispatchMouseEvent
    ok(!grep({ $_ eq 'Target.activateTarget' } @methods),
       'js click: no activateTarget');
    ok(!grep({ $_ eq 'Input.dispatchMouseEvent' } @methods),
       'js click: no mouse events');

    # Should have resolveNode + callFunctionOn with .click()
    ok(grep({ $_ eq 'DOM.resolveNode' } @methods), 'js click: resolves node');
    ok(grep({ $_ eq 'Runtime.callFunctionOn' } @methods), 'js click: calls .click()');

    like($out, qr/js/, 'js click: output mentions js');
}

done_testing;
