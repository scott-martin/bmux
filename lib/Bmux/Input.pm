package Bmux::Input;
use strict;
use warnings;
use JSON::PP;

# DOM.querySelector — find a node by CSS selector
sub cmd_query_selector {
    my ($cdp, $node_id, $selector) = @_;
    return $cdp->build_command('DOM.querySelector', {
        nodeId   => $node_id,
        selector => $selector,
    });
}

# DOM.getBoxModel — get element dimensions for click targeting
sub cmd_get_box_model {
    my ($cdp, $node_id) = @_;
    return $cdp->build_command('DOM.getBoxModel', { nodeId => $node_id });
}

# Compute center point of a content quad (8 values: x1,y1,x2,y2,x3,y3,x4,y4)
sub center_of_quad {
    my @q = @_;
    my $x = ($q[0] + $q[2] + $q[4] + $q[6]) / 4;
    my $y = ($q[1] + $q[3] + $q[5] + $q[7]) / 4;
    return (int($x), int($y));
}

# Target.activateTarget — bring browser window to OS foreground.
# The browser process itself calls SetForegroundWindow, which Windows allows.
# This is how Playwright makes coordinate-based clicks work.
sub cmd_activate_target {
    my ($cdp, $target_id) = @_;
    return $cdp->build_command('Target.activateTarget', {
        targetId => $target_id,
    });
}

# Input.dispatchMouseEvent — mouseMoved (hover before click)
sub cmd_mouse_moved {
    my ($cdp, $x, $y) = @_;
    return $cdp->build_command('Input.dispatchMouseEvent', {
        type => 'mouseMoved',
        x    => $x,
        y    => $y,
    });
}

# Input.dispatchMouseEvent — mousePressed
sub cmd_mouse_pressed {
    my ($cdp, $x, $y) = @_;
    return $cdp->build_command('Input.dispatchMouseEvent', {
        type       => 'mousePressed',
        x          => $x,
        y          => $y,
        button     => 'left',
        clickCount => 1,
    });
}

# Input.dispatchMouseEvent — mouseReleased
sub cmd_mouse_released {
    my ($cdp, $x, $y) = @_;
    return $cdp->build_command('Input.dispatchMouseEvent', {
        type       => 'mouseReleased',
        x          => $x,
        y          => $y,
        button     => 'left',
        clickCount => 1,
    });
}

# DOM.focus — focus an element
sub cmd_focus {
    my ($cdp, $node_id) = @_;
    return $cdp->build_command('DOM.focus', { nodeId => $node_id });
}

# Set value of an input via JS (used by fill)
sub cmd_set_value {
    my ($cdp, $node_id, $value) = @_;
    my $escaped = $value;
    $escaped =~ s/\\/\\\\/g;
    $escaped =~ s/'/\\'/g;
    my $js = qq{
        (function() {
            var node = document.querySelector('[data-bmux-id="$node_id"]');
            if (!node) {
                var all = document.querySelectorAll('*');
                // fallback: use Runtime to resolve
            }
            // Use CDP's resolved node — set via backendNodeId
            return true;
        })()
    };
    # Simpler approach: resolve node to JS object first, then set value
    # In practice, we'll use DOM.resolveNode + Runtime.callFunctionOn
    # For now, build a Runtime.evaluate that the dispatcher will use
    # after resolving the selector to a remote object
    return $cdp->build_command('Runtime.evaluate', {
        expression => qq{
            (function() {
                var el = document.querySelector('[data-bmux-target]');
                el.value = '$escaped';
                el.dispatchEvent(new Event('input', {bubbles: true}));
                return true;
            })()
        },
    });
}

# DOM.resolveNode — get JS remote object for a DOM node
sub cmd_resolve_node {
    my ($cdp, $node_id) = @_;
    return $cdp->build_command('DOM.resolveNode', { nodeId => $node_id });
}

# Runtime.callFunctionOn — call .click() on a resolved JS object
# Fallback click method (--js flag). Used when coordinate clicks aren't
# needed. Coordinate clicks are now the default — we use
# Target.activateTarget to bring the window to foreground first,
# which works because the browser process itself calls SetForegroundWindow.
sub cmd_js_click {
    my ($cdp, $object_id) = @_;
    return $cdp->build_command('Runtime.callFunctionOn', {
        objectId            => $object_id,
        functionDeclaration => 'function() { this.click() }',
    });
}

# Input.dispatchKeyEvent — single keystroke
sub cmd_key_event {
    my ($cdp, $type, $text) = @_;
    return $cdp->build_command('Input.dispatchKeyEvent', {
        type => $type,
        text => $text,
    });
}

# --- High-level command handlers (called from dispatcher) ---

# Dispatch a coordinate-based click: move → press → release
sub dispatch_click {
    my ($cdp, $x, $y) = @_;
    $cdp->send_command('Input.dispatchMouseEvent', {
        type => 'mouseMoved', x => $x, y => $y,
    });
    $cdp->send_command('Input.dispatchMouseEvent', {
        type => 'mousePressed', x => $x, y => $y,
        button => 'left', clickCount => 1,
    });
    $cdp->send_command('Input.dispatchMouseEvent', {
        type => 'mouseReleased', x => $x, y => $y,
        button => 'left', clickCount => 1,
    });
}

sub _resolve_node {
    my ($cdp, $selector) = @_;
    my $doc = $cdp->send_command('DOM.getDocument');
    my $root_id = $doc->{root}{nodeId};
    my $node = $cdp->send_command('DOM.querySelector', {
        nodeId => $root_id, selector => $selector,
    });
    my $nid = $node->{nodeId} // 0;
    die "No element found: $selector\n" unless $nid;
    return ($root_id, $nid);
}

sub run_click {
    my ($cdp, $parsed) = @_;
    my $selector = $parsed->{object} // die "Usage: bmux click <selector>\n";
    my $use_js = $parsed->{modifiers} && $parsed->{modifiers}{'--js'};

    my (undef, $nid) = _resolve_node($cdp, $selector);

    if ($use_js) {
        # Fallback: JS click (works without focus, but misses some handlers)
        my $resolved = $cdp->send_command('DOM.resolveNode', { nodeId => $nid });
        my $obj_id = $resolved->{object}{objectId};
        $cdp->send_command('Runtime.callFunctionOn', {
            objectId            => $obj_id,
            functionDeclaration => 'function() { this.click() }',
        });
        print "Clicked $selector (js)\n";
        return;
    }

    # Coordinate-based click — the real deal.
    # Step 1: Bring browser window to foreground via Target.activateTarget.
    # This works because the *browser process* calls SetForegroundWindow,
    # not us. Windows allows a process to foreground its own windows.
    # This is exactly what Playwright does.
    if ($cdp->{target_id}) {
        $cdp->send_command('Target.activateTarget', {
            targetId => $cdp->{target_id},
        });
        # Brief pause for window manager to process the focus change
        select(undef, undef, undef, 0.1);
    }

    # Step 2: Scroll element into view and get its coordinates
    my $resolved = $cdp->send_command('DOM.resolveNode', { nodeId => $nid });
    my $obj_id = $resolved->{object}{objectId};

    # scrollIntoViewIfNeeded — same as Playwright uses
    $cdp->send_command('Runtime.callFunctionOn', {
        objectId            => $obj_id,
        functionDeclaration => 'function() { this.scrollIntoViewIfNeeded ? this.scrollIntoViewIfNeeded() : this.scrollIntoView({block:"center",inline:"center"}) }',
    });

    # Step 3: Get box model for center coordinates
    my $box = $cdp->send_command('DOM.getBoxModel', { nodeId => $nid });
    my @content = @{$box->{model}{content}};
    my ($x, $y) = center_of_quad(@content);

    # Step 4: Dispatch mouse events (move → down → up)
    dispatch_click($cdp, $x, $y);

    print "Clicked $selector at ($x, $y)\n";
}

sub run_fill {
    my ($cdp, $parsed) = @_;
    my $selector = $parsed->{object} // die "Usage: bmux fill <selector> <value>\n";
    my $value = $parsed->{value} // die "Usage: bmux fill <selector> <value>\n";

    my (undef, $nid) = _resolve_node($cdp, $selector);
    $cdp->send_command('DOM.focus', { nodeId => $nid });

    my $resolved = $cdp->send_command('DOM.resolveNode', { nodeId => $nid });
    my $obj_id = $resolved->{object}{objectId};

    $cdp->send_command('Runtime.callFunctionOn', {
        objectId            => $obj_id,
        functionDeclaration => q{
            function(val) {
                this.value = val;
                this.dispatchEvent(new Event('input', {bubbles: true}));
                this.dispatchEvent(new Event('change', {bubbles: true}));
            }
        },
        arguments => [{ value => $value }],
    });
    print "Filled $selector\n";
}

sub run_type {
    my ($cdp, $parsed) = @_;
    my $selector = $parsed->{object} // die "Usage: bmux type <selector> <text>\n";
    my $text = $parsed->{value} // die "Usage: bmux type <selector> <text>\n";

    my (undef, $nid) = _resolve_node($cdp, $selector);
    $cdp->send_command('DOM.focus', { nodeId => $nid });

    for my $char (split //, $text) {
        $cdp->send_command('Input.dispatchKeyEvent', { type => 'keyDown', text => $char });
        $cdp->send_command('Input.dispatchKeyEvent', { type => 'keyUp',   text => $char });
    }
    print "Typed into $selector\n";
}

sub run_wait {
    my ($cdp, $parsed) = @_;
    my $selector = $parsed->{object} // die "Usage: bmux wait <selector>\n";
    my $timeout = 30;

    my $start = time();
    while (time() - $start < $timeout) {
        eval {
            my $doc = $cdp->send_command('DOM.getDocument');
            my $node = $cdp->send_command('DOM.querySelector', {
                nodeId => $doc->{root}{nodeId}, selector => $selector,
            });
            if (($node->{nodeId} // 0) > 0) {
                print "Found: $selector\n";
                die "FOUND\n";  # break out of eval+while
            }
        };
        return if $@ && $@ =~ /FOUND/;
        sleep 1;
    }
    die "Timeout waiting for: $selector\n";
}

1;
