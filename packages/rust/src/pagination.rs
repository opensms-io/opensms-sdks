//! Cursor auto-pagination.
//!
//! [`Paginator`] repeatedly calls a list method, feeding each page's
//! `next_cursor` back as `cursor` until it is `None`, and yields items lazily.
//! Only cursor lists are supported; bare-array endpoints and the wallet
//! ledger (which pages by `before`) are not.

use std::collections::VecDeque;
use std::future::Future;

use crate::error::Result;
use crate::models::Page;

/// Lazily walks every page of a cursor list. Create with
/// [`crate::Client::paginate`] or [`paginate`].
///
/// ```no_run
/// # async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
/// use opensms::ListMessages;
///
/// let mut it = client.paginate(|cursor| {
///     client.messages().list(ListMessages { limit: Some(50), cursor, ..Default::default() })
/// });
/// while let Some(message) = it.next().await {
///     println!("{}", message?.id);
/// }
/// # Ok(())
/// # }
/// ```
pub struct Paginator<T, F> {
    fetch: F,
    buffer: VecDeque<T>,
    cursor: Option<String>,
    done: bool,
}

/// Build a [`Paginator`] from a closure that fetches one page given the
/// cursor (`None` for the first page).
pub fn paginate<T, F, Fut>(fetch: F) -> Paginator<T, F>
where
    F: FnMut(Option<String>) -> Fut,
    Fut: Future<Output = Result<Page<T>>>,
{
    Paginator {
        fetch,
        buffer: VecDeque::new(),
        cursor: None,
        done: false,
    }
}

impl<T, F, Fut> Paginator<T, F>
where
    F: FnMut(Option<String>) -> Fut,
    Fut: Future<Output = Result<Page<T>>>,
{
    /// The next item, fetching the next page when needed. `None` when every
    /// page has been read. After an error, iteration stops.
    pub async fn next(&mut self) -> Option<Result<T>> {
        loop {
            if let Some(item) = self.buffer.pop_front() {
                return Some(Ok(item));
            }
            if self.done {
                return None;
            }
            match (self.fetch)(self.cursor.take()).await {
                Ok(page) => {
                    self.buffer.extend(page.items);
                    match page.next_cursor {
                        Some(c) if !c.is_empty() => self.cursor = Some(c),
                        _ => self.done = true,
                    }
                }
                Err(e) => {
                    self.done = true;
                    return Some(Err(e));
                }
            }
        }
    }

    /// Read every remaining item into a `Vec`.
    pub async fn collect_all(mut self) -> Result<Vec<T>> {
        let mut out = Vec::new();
        while let Some(item) = self.next().await {
            out.push(item?);
        }
        Ok(out)
    }
}
