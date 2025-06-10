mod app;
mod command;
mod execution;
mod models;
mod persistence;
mod ui;

use app::App;
use crossterm::{
    event::{DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::{error::Error, io, time::Duration};
use ui::{Event, EventHandler, Theme};
use ui::components::{
    CommandBuilder, CommandDisplay, OptionsPanel, OutputPanel, TemplatesTree,
};

fn main() -> Result<(), Box<dyn Error>> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app state
    let app = App::new();
    
    // Create UI theme
    let theme = Theme::new();
    
    // Create event handler
    let events = EventHandler::new(Duration::from_millis(100));
    
    // Run app
    let res = run_app(&mut terminal, app, theme, events);
    
    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;
    
    if let Err(err) = res {
        println!("{:?}", err);
    }
    
    Ok(())
}

fn run_app<B: ratatui::backend::Backend>(
    terminal: &mut Terminal<B>,
    mut app: App,
    theme: Theme,
    events: EventHandler,
) -> io::Result<()> {
    loop {
        // Draw UI
        terminal.draw(|f| {
            let size = f.size();
            
            // Create layout
            let chunks = ratatui::layout::Layout::default()
                .direction(ratatui::layout::Direction::Vertical)
                .constraints([
                    ratatui::layout::Constraint::Percentage(20), // Templates and command builder
                    ratatui::layout::Constraint::Percentage(10), // Command display
                    ratatui::layout::Constraint::Percentage(70), // Output
                ])
                .split(size);
            
            // Create horizontal layout for top section
            let top_chunks = ratatui::layout::Layout::default()
                .direction(ratatui::layout::Direction::Horizontal)
                .constraints([
                    ratatui::layout::Constraint::Percentage(20), // Templates
                    ratatui::layout::Constraint::Percentage(80), // Command builder
                ])
                .split(chunks[0]);
            
            // Render templates
            let templates_tree = TemplatesTree::new(&app, &theme);
            templates_tree.render(f, top_chunks[0]);
            
            // Render command builder
            let command_builder = CommandBuilder::new(&app, &theme);
            command_builder.render(f, top_chunks[1]);
            
            // Render command display
            let command_display = CommandDisplay::new(&app, &theme);
            command_display.render(f, chunks[1]);
            
            // Render output
            let output_panel = OutputPanel::new(&app, &theme);
            output_panel.render(f, chunks[2]);
        })?;
        
        // Handle events
        if let Ok(event) = events.next() {
            match event {
                Event::Key(key) => {
                    if app.handle_event(&crossterm::event::Event::Key(key)) {
                        return Ok(());
                    }
                }
                Event::Tick => {
                    app.update_command();
                }
                _ => {}
            }
        } else {
            // Handle RecvError (channel closed)
            return Ok(());
        }
    }
}
