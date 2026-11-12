#![cfg(target_os = "macos")]
mod native;
use anotchup_gates::{DisplayLifetimes, Lifetime};
use core_video::pixel_buffer::CVPixelBuffer;
use gpui::{
    Animation, AnimationExt, App, Bounds, Context, FocusHandle, KeyDownEvent,
    MacosWindowBackground, ObjectFit, Render, Subscription, Window, WindowBounds, WindowKind,
    WindowOptions, div, linear_color_stop, linear_gradient, point, prelude::*, px, rgb, rgba, size,
    surface,
};
use std::{cell::RefCell, rc::Rc, time::Duration};

struct Gate {
    registry: Rc<RefCell<DisplayLifetimes>>,
    lifetime: Lifetime,
    focus: FocusHandle,
    subscriptions: Vec<Subscription>,
    frame: CVPixelBuffer,
    phase: usize,
    mirrored: bool,
    expanded: bool,
    pulsing: bool,
    text: String,
}
impl Drop for Gate {
    fn drop(&mut self) {
        self.registry.borrow_mut().remove(self.lifetime);
    }
}
impl Gate {
    fn new(
        id: u64,
        registry: Rc<RefCell<DisplayLifetimes>>,
        script: Script,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let lifetime = registry.borrow_mut().register(id);
        let mut gate = Self {
            registry,
            lifetime,
            focus: cx.focus_handle(),
            subscriptions: vec![],
            frame: native::frame(0, false),
            phase: 0,
            mirrored: false,
            expanded: false,
            pulsing: false,
            text: String::new(),
        };
        gate.subscriptions
            .push(cx.observe_window_bounds(window, |_, window, _| {
                let viewport = window.viewport_size();
                eprintln!(
                    "[resize] gpui viewport={}x{}",
                    f32::from(viewport.width),
                    f32::from(viewport.height)
                );
                assert!(native::mask(window), "native mask update failed");
            }));
        if !script.steps.is_empty() {
            // Input-free diagnostic: the same code paths as the buttons, no pointer or keys.
            // "begin" is deliberately absent: it would take keyboard focus from the owner.
            cx.spawn_in(window, async move |this, cx| {
                for step in script.steps.iter() {
                    cx.background_executor().timer(script.interval).await;
                    if this
                        .update_in(cx, |this, window, cx| this.step(step, window, cx))
                        .is_err()
                    {
                        break;
                    }
                }
            })
            .detach();
        }
        gate.subscriptions
            .push(cx.observe_window_activation(window, |this, window, cx| {
                if window.is_window_active() {
                    this.registry.borrow_mut().became_key(this.lifetime);
                } else {
                    this.registry.borrow_mut().resigned_key(this.lifetime);
                    native::edit(window, false);
                    eprintln!("[edit] off resigned");
                }
                cx.notify();
            }));
        gate
    }
    fn step(&mut self, step: &str, window: &mut Window, cx: &mut Context<Self>) {
        eprintln!("[step] {step}");
        match step {
            "frame" => self.next_frame(cx),
            "mirror" => self.toggle_mirror(cx),
            "resize" => self.toggle_size(window, cx),
            "pulse" => {
                self.pulsing = !self.pulsing;
                cx.notify();
            }
            "remove" => window.remove_window(),
            "quit" => cx.quit(),
            _ => unreachable!("steps are validated at startup"),
        }
    }
    fn next_frame(&mut self, cx: &mut Context<Self>) {
        self.phase = (self.phase + 24) % 320;
        eprintln!("[action] frame phase={}", self.phase);
        self.frame = native::frame(self.phase, self.mirrored);
        cx.notify();
    }
    fn toggle_mirror(&mut self, cx: &mut Context<Self>) {
        self.mirrored = !self.mirrored;
        eprintln!("[action] mirror mirrored={}", self.mirrored);
        self.frame = native::frame(self.phase, self.mirrored);
        cx.notify();
    }
    fn toggle_size(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.expanded = !self.expanded;
        eprintln!("[action] resize expanded={}", self.expanded);
        let (width, height) = if self.expanded {
            (680., 390.)
        } else {
            (560., 320.)
        };
        native::resize(window, width, height);
        cx.notify();
    }
    fn begin(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.registry.borrow_mut().begin_editing(self.lifetime) {
            self.focus.focus(window, cx);
            let native = native::edit(window, true);
            eprintln!("[edit] on native={native}");
            cx.notify();
        }
    }
    fn end(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.registry.borrow_mut().resigned_key(self.lifetime);
        native::edit(window, false);
        eprintln!("[edit] off end");
        cx.notify();
    }
    fn key(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        if !self.registry.borrow().can_become_key(self.lifetime) || !native::is_editing(window) {
            return;
        }
        match event.keystroke.key.as_str() {
            "escape" | "enter" => self.end(window, cx),
            "backspace" => {
                self.text.pop();
            }
            _ => {
                if let Some(ch) = &event.keystroke.key_char {
                    self.text.push_str(ch);
                }
            }
        }
        eprintln!("[key] {} text={}", event.keystroke.key, self.text);
        cx.notify();
    }
}
impl Render for Gate {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        // Read native state after outside-click resign; this is a keyboard probe, not an IME editor.
        let editing = native::is_editing(window);
        div().id("gate").track_focus(&self.focus).on_key_down(cx.listener(Self::key))
            .on_hover(|hovered,_,_|eprintln!("[hover] panel={hovered}"))
            .size_full().flex().flex_col().gap_2().p_4().text_color(rgb(0xffffff)).font_family("Helvetica Neue")
            .bg(linear_gradient(90.0,linear_color_stop(rgb(0x213554),0.0),linear_color_stop(rgb(0x752752),1.0)))
            // Deliberately reach every edge: the native mask must clip this subtree, not just its background.
            .child(div().absolute().top(px(0.)).left(px(-10.)).w(px(1000.)).h(px(8.)).bg(rgb(0x00ffb3)))
            .child(format!("GPUI-CE gate | {} | synthetic only",if editing {"KEY"} else {"non-key"}))
            .child(div().flex().gap_2()
                .child(div().id("edit").px_2().bg(rgb(0x456080)).cursor_pointer().child("Begin typing probe").on_click(cx.listener(|this,_,window,cx|this.begin(window,cx))))
                .child(div().id("end").px_2().bg(rgb(0x456080)).cursor_pointer().child("End / Esc").on_click(cx.listener(|this,_,window,cx|this.end(window,cx))))
                .child(div().id("quit").px_2().bg(rgb(0x803050)).cursor_pointer().child("Quit").on_click(|_,_,cx|cx.quit())))
            .child(format!("Keys: {}",self.text))
            .child(div().flex().gap_4()
                .child(div().flex_none().w(px(210.)).h(px(130.)).overflow_hidden().child(surface(self.frame.clone()).object_fit(ObjectFit::Cover).size_full()))
                .child(div().flex_1().min_w_0().flex().flex_col().gap_3()
                    .child(div().blur(px(2.)).child("CE subtree blur fixture"))
                    .child(div().bg(rgba(0xffffff30)).backdrop_blur(px(8.)).p_2().child("Backdrop fixture"))
                    .child("Video corners deliberately square: separate camera mask still open.")))
            .child(div().flex().gap_2()
                .child(div().id("frame").px_2().bg(rgb(0x456080)).hover_style(|style|style.bg(rgb(0x9fd0ff))).cursor_pointer().child("Next frame").on_click(cx.listener(|this,_,_,cx|this.next_frame(cx))))
                .child(div().id("mirror").px_2().bg(rgb(0x456080)).cursor_pointer().child(if self.mirrored {"Mirrored"} else {"Mirror"}).on_click(cx.listener(|this,_,_,cx|this.toggle_mirror(cx))))
                .child(div().id("resize").px_2().bg(rgb(0x456080)).cursor_pointer().child("Resize").on_click(cx.listener(|this,_,window,cx|this.toggle_size(window,cx))))
                .child(div().id("close").px_2().bg(rgb(0x456080)).cursor_pointer().child("Remove display probe").on_click(|_,window,_|window.remove_window())))
            // Scripted only: a repeating animation must keep the display link alive, then let it stop.
            .when(self.pulsing, |this| this.child(div().absolute().top(px(12.)).right(px(16.)).size(px(14.)).bg(rgb(0xffd000)).with_animation("pulse",Animation::new(Duration::from_millis(600)).repeat(),|dot,phase|dot.opacity(0.2+0.8*phase))))
            .child("No camera, preferences, private SkyLight, or installed-app integration. IME is not implemented.")
    }
}
/// Timed button actions for checks that must not use the owner's input devices.
#[derive(Clone)]
struct Script {
    steps: Rc<[String]>,
    interval: Duration,
}
impl Script {
    fn parse(args: &[String]) -> Option<Self> {
        let (first, mut rest) = args.split_first()?;
        if first != "--show" {
            return None;
        }
        let mut steps = vec![];
        let mut interval = 3000;
        while let [flag, value, tail @ ..] = rest {
            match flag.as_str() {
                "--steps" => steps = value.split(',').map(str::to_owned).collect(),
                "--step-ms" => interval = value.parse().ok().filter(|ms| *ms >= 50)?,
                _ => return None,
            }
            rest = tail;
        }
        let known = ["frame", "mirror", "resize", "pulse", "remove", "quit"];
        (rest.is_empty() && steps.iter().all(|step| known.contains(&step.as_str()))).then(|| Self {
            steps: steps.into(),
            interval: Duration::from_millis(interval),
        })
    }
}
fn main() {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args == ["--check-native"] {
        assert!(
            native::contracts(),
            "native CoreVideo/CoreGraphics contracts failed"
        );
        println!(
            "Native frame idle policy, popup style, placement arithmetic, frame constraint, block lifetime, popup initializer, buffer format, plane copy, invalid format and path contracts passed (no windows or camera)."
        );
        return;
    }
    let script = Script::parse(&args);
    if script.is_none() {
        println!(
            "anotchup-gates\n  --check-native  Headless ABI, block, buffer and path contracts\n  --show          Explicitly open synthetic panels on connected displays\n  --show --steps frame,mirror,resize,pulse,remove,quit [--step-ms N]\n                  Also run those button actions on a timer (no input events)\nNo installed app, user preferences, camera or permissions are accessed."
        );
        if !args.is_empty() {
            std::process::exit(2);
        }
        return;
    }
    let script = script.expect("validated above");
    eprintln!("[startup] entering GPUI event loop");
    gpui_platform::application().run(move |cx: &mut App| {
        let displays = cx.displays();
        eprintln!("[startup] opening probes on {} display(s)", displays.len());
        cx.on_window_closed(|cx, _| {
            if cx.windows().is_empty() {
                cx.quit();
            }
        })
        .detach();
        let registry = Rc::new(RefCell::new(DisplayLifetimes::default()));
        for (index, display) in displays.into_iter().enumerate() {
            eprintln!("[startup] creating display {index} popup");
            let screen = display.bounds();
            let bounds = Bounds::new(
                point(
                    screen.origin.x + (screen.size.width - px(560.)) / 2.,
                    screen.origin.y,
                ),
                size(px(560.), px(320.)),
            );
            let registry = registry.clone();
            let script = script.clone();
            cx.open_window(
                WindowOptions {
                    window_bounds: Some(WindowBounds::Windowed(bounds)),
                    titlebar: None,
                    focus: false,
                    show: false,
                    kind: WindowKind::PopUp,
                    is_movable: false,
                    is_resizable: false,
                    is_minimizable: false,
                    display_id: Some(display.id()),
                    macos_window_background: MacosWindowBackground::Transparent,
                    ..Default::default()
                },
                move |window, cx| {
                    eprintln!("[startup] configuring display {index} native panel");
                    assert!(
                        native::install(window),
                        "CE native panel shape changed; refusing unguarded window"
                    );
                    let view = cx.new(|cx| Gate::new(index as u64, registry, script, window, cx));
                    assert!(native::mask(window), "native mask installation failed");
                    native::show(window);
                    view
                },
            )
            .expect("create hidden gate window");
            eprintln!("[startup] display {index} probe ready");
        }
    });
}
