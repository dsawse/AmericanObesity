use godot::init::{gdextension, ExtensionLibrary, InitLevel};

pub(crate) mod engine {
    pub(crate) struct Engine;
}
pub mod clicker_game;
mod raw_engine_init {
    use godot::{
        init::InitLevel,
        obj::NewAlloc,
        register::{godot_api, GodotClass},
    };
    use std::sync::atomic::{AtomicBool, Ordering::Relaxed};

    static INITIALIZED: AtomicBool = AtomicBool::new(false);

    #[derive(GodotClass)]
    #[class(base = Object, init)]
    struct RuntimeGuard {}

    #[godot_api]
    impl RuntimeGuard {
        #[func]
        pub fn rt_guard_init(&self) {
            INITIALIZED.store(true, Relaxed);
        }
    }

    // Godot calls this when it loads this extension.
    // This must run through Godot otherwise we bypass
    // knowledge of a failure to load this extension.
    pub fn initialization_check(level: InitLevel) {
        if level != InitLevel::Servers {
            return;
        }
        // We must only run this once
        assert!(!INITIALIZED.swap(true, Relaxed));
        let mut guard = RuntimeGuard::new_alloc();
        guard.call("rt_guard_init", &[]);
        guard.free();
    }
}

#[gdextension(entry_symbol = engine_init)]
unsafe impl ExtensionLibrary for engine::Engine {
    fn on_level_init(level: InitLevel) {
        raw_engine_init::initialization_check(level);
        println!("[engine]::on_level_init() called");
    }

    fn on_level_deinit(_level: InitLevel) {
        // TODO: clean up, if needed
        println!("[engine]::on_level_deinit() called");
    }
}
