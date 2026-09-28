/**
 * Lightweight citation system for Reveal.js presentations
 *
 * Usage:
 *   Inline/narrative (auto-fill):   <cite key="smith2020"></cite>
 *   Inline (explicit text):          <cite key="smith2020">Smith et al. (2020)</cite>
 *   Parenthetical (auto-fill):       <cite key="smith2020" parens></cite>
 *
 * Auto-fill formats:
 *   (no parens attr)  → "Author (Year)"   e.g. "Smith & Jones (2020)"
 *   (parens attr)     → "(Author, Year)"  e.g. "(Smith & Jones, 2020)"
 *
 * The script will:
 *   1. Link citations to their DOIs (if doi field present in references.json)
 *   2. Generate a bibliography in the element with id="bibliography"
 *   3. Paginate bibliography at REFS_PER_PAGE refs per slide
 *   4. Validate all citation keys, logging errors to the console
 */

(function() {
  'use strict';

  const REFS_PER_PAGE = 7;

  let references = {};
  const citedKeys = new Set();
  const missingKeys = new Set();

  // Extract the short author string used by both citation formats
  function shortAuthors(ref) {
    const authors = ref.authors;
    if (authors.includes('...')) {
      return authors.split(',')[0] + ' et al.';
    }
    const hasAmpersand = authors.includes(' & ');
    const preAmpersand = hasAmpersand ? authors.split(' & ')[0] : authors;
    const separatorCount = (preAmpersand.match(/\., /g) || []).length;
    const authorCount = separatorCount + (hasAmpersand ? 2 : 1);
    if (authorCount > 2) {
      return authors.split(',')[0] + ' et al.';
    } else if (hasAmpersand) {
      const parts = authors.split(' & ');
      return `${parts[0].split(',')[0]} & ${parts[1].split(',')[0]}`;
    }
    return authors.split(',')[0];
  }

  // Inline style: Author (Year)
  function formatShortCite(ref) {
    return `${shortAuthors(ref)} (${ref.year})`;
  }

  // Parenthetical style: (Author, Year)
  function formatParentheticalCite(ref) {
    return `(${shortAuthors(ref)}, ${ref.year})`;
  }

  // Inner parenthetical (no brackets), used when grouping adjacent cites:
  //   "Author, Year"  →  joined as "(A, 2024; B, 2025)"
  function formatInnerParenthetical(ref) {
    return `${shortAuthors(ref)}, ${ref.year}`;
  }

  function citeHref(ref) {
    return ref.doi ? `https://doi.org/${ref.doi}` : (ref.url || null);
  }

  // Build a linked <a> (or a bare text node when there is no DOI/url)
  function linkedNode(text, ref) {
    const href = citeHref(ref);
    if (!href) return document.createTextNode(text);
    const a = document.createElement('a');
    a.href = href;
    a.target = '_blank';
    a.textContent = text;
    return a;
  }

  // An unrendered parenthetical cite with a valid key, eligible for grouping.
  function isGroupableParensCite(node) {
    return node && node.nodeType === 1 && node.tagName === 'CITE'
      && node.hasAttribute('parens') && node.hasAttribute('key')
      && references[node.getAttribute('key')]
      && !node.querySelector('a')                  // not already rendered
      && !node.hasAttribute('data-cite-merged')    // not already merged away
      && !node.textContent.trim();                 // no explicit text
  }

  // Format a full bibliography entry
  function formatBibEntry(key, ref) {
    let entry = `${ref.authors} (${ref.year}). ${ref.title}.`;

    if (ref.journal) {
      entry += ` <em>${ref.journal}</em>`;
      if (ref.volume) {
        entry += `, <em>${ref.volume}</em>`;
        if (ref.issue) {
          entry += `(${ref.issue})`;
        }
      }
      if (ref.pages) {
        entry += `, ${ref.pages}`;
      }
      entry += '.';
    } else if (ref.publisher) {
      entry += ` ${ref.publisher}.`;
    }

    if (ref.doi) {
      entry += ` <a href="https://doi.org/${ref.doi}" target="_blank">https://doi.org/${ref.doi}</a>`;
    } else if (ref.url) {
      entry += ` <a href="${ref.url}" target="_blank">${ref.url}</a>`;
    }

    return entry;
  }

  // Process all citation elements. Idempotent: a cite that already holds a
  // rendered <a>, or has been merged into a group, is left untouched — so it
  // is safe to re-run after the rendered DOM has been saved back to source
  // (as the slide-comments overlay does).
  function processCitations() {
    const cites = Array.from(document.querySelectorAll('cite[key]'));
    const handled = new Set();

    cites.forEach(cite => {
      if (handled.has(cite)) return;
      if (cite.hasAttribute('data-cite-merged')) return;   // emptied by a prior group

      const key = cite.getAttribute('key');

      if (!references[key]) {
        missingKeys.add(key);
        cite.style.color = 'red';
        cite.style.fontWeight = 'bold';
        cite.title = `Missing reference: ${key}`;
        if (!cite.textContent.trim()) cite.textContent = `[MISSING: ${key}]`;
        return;
      }

      citedKeys.add(key);

      // Already rendered (contains a link) → leave as-is. Prevents the
      // "(Author, Year)" → "(Author (Year))" double-bracket on re-runs.
      if (cite.querySelector('a')) { handled.add(cite); return; }

      // Group a run of adjacent parenthetical cites into one bracket:
      //   <cite parens></cite> <cite parens></cite>  →  (A, 2024; B, 2025)
      if (cite.hasAttribute('parens') && !cite.textContent.trim()) {
        const group = [cite];
        let node = cite.nextSibling;
        while (node) {
          if (node.nodeType === 3 && !node.textContent.trim()) { node = node.nextSibling; continue; }
          if (isGroupableParensCite(node)) { group.push(node); node = node.nextSibling; continue; }
          break;
        }
        if (group.length > 1) {
          cite.textContent = '';
          cite.appendChild(document.createTextNode('('));
          group.forEach((c, i) => {
            const ref = references[c.getAttribute('key')];
            citedKeys.add(c.getAttribute('key'));
            if (i > 0) {
              cite.appendChild(document.createTextNode('; '));
              c.textContent = '';
              c.setAttribute('data-cite-merged', '');
              handled.add(c);
            }
            cite.appendChild(linkedNode(formatInnerParenthetical(ref), ref));
          });
          cite.appendChild(document.createTextNode(')'));
          handled.add(cite);
          return;
        }
      }

      // Single cite
      const ref = references[key];
      const text = cite.textContent.trim()
        ? cite.textContent.replace(/,\s*(\d{4})\b/, ' ($1)')   // explicit text: "Name, Year" → "Name (Year)"
        : (cite.hasAttribute('parens') ? formatParentheticalCite(ref) : formatShortCite(ref));
      cite.textContent = '';
      cite.appendChild(linkedNode(text, ref));
      handled.add(cite);
    });
  }

  // Generate bibliography with pagination across slides
  function generateBibliography() {
    const bibElement = document.getElementById('bibliography');
    if (!bibElement) return;

    if (citedKeys.size === 0) {
      bibElement.innerHTML = '<p><em>No citations found.</em></p>';
      return;
    }

    // Sort by author surname, then year
    const sortedKeys = Array.from(citedKeys).sort((a, b) => {
      const refA = references[a];
      const refB = references[b];
      const authorA = refA.authors.split(',')[0].toLowerCase();
      const authorB = refB.authors.split(',')[0].toLowerCase();
      if (authorA !== authorB) return authorA.localeCompare(authorB);
      return refA.year - refB.year;
    });

    const totalPages = Math.ceil(sortedKeys.length / REFS_PER_PAGE);

    // Get the parent section element
    const parentSection = bibElement.closest('section');
    let lastInsertedSection = parentSection;

    // Update the first page heading with page count
    const firstHeading = parentSection.querySelector('h2');
    if (firstHeading && totalPages > 1) {
      firstHeading.textContent = `References (1/${totalPages})`;
    }

    for (let page = 0; page < totalPages; page++) {
      const startIdx = page * REFS_PER_PAGE;
      const endIdx = Math.min(startIdx + REFS_PER_PAGE, sortedKeys.length);
      const pageKeys = sortedKeys.slice(startIdx, endIdx);

      const ul = document.createElement('ul');
      ul.style.listStyleType = 'none';
      ul.style.paddingLeft = '0';

      pageKeys.forEach(key => {
        const li = document.createElement('li');
        li.style.marginBottom = '0.5em';
        li.innerHTML = formatBibEntry(key, references[key]);
        ul.appendChild(li);
      });

      if (page === 0) {
        // First page goes in the existing bibliography element
        bibElement.appendChild(ul);
      } else {
        // Create new slides for subsequent pages. Mirror the original
        // section's classes and wrap the list in a .bibliography div so
        // CSS rules apply consistently across paginated pages.
        const newSection = document.createElement('section');
        if (parentSection.className) newSection.className = parentSection.className;
        const heading = document.createElement('h2');
        heading.textContent = `References (${page + 1}/${totalPages})`;
        newSection.appendChild(heading);
        const bibWrap = document.createElement('div');
        bibWrap.className = 'bibliography';
        bibWrap.appendChild(ul);
        newSection.appendChild(bibWrap);
        lastInsertedSection.parentNode.insertBefore(newSection, lastInsertedSection.nextSibling);
        lastInsertedSection = newSection;
      }
    }
  }

  // Report validation results to console
  function reportValidation() {
    console.log(`Citations: ${citedKeys.size} used, ${Object.keys(references).length} in references.json`);

    if (missingKeys.size > 0) {
      console.error('MISSING REFERENCES:', Array.from(missingKeys));
    }

    const unusedKeys = Object.keys(references).filter(k => !citedKeys.has(k));
    if (unusedKeys.length > 0) {
      console.warn('Unused references:', unusedKeys);
    }
  }

  // Initialize
  async function init() {
    try {
      const response = await fetch('references.json');
      if (!response.ok) {
        throw new Error(`Failed to load references.json: ${response.status}`);
      }
      references = await response.json();

      processCitations();
      generateBibliography();
      reportValidation();

      // Sync Reveal.js so it picks up dynamically added reference slides
      if (typeof Reveal !== 'undefined' && Reveal.sync) {
        Reveal.sync();
      }

    } catch (error) {
      console.error('Citation system error:', error);
      document.querySelectorAll('cite[key]').forEach(cite => {
        cite.style.color = 'orange';
        cite.title = 'Failed to load references';
      });
    }
  }

  // Run when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
