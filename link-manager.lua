-- =============================================================
-- HAMMERSPOON CONFIG
-- =============================================================

-- Auto-reload config when file changes
function reloadConfig(files)
    local doReload = false
    for _, file in pairs(files) do
        if file:sub(-4) == ".lua" then
            doReload = true
        end
    end
    if doReload then
        hs.reload()
    end
end
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()

-- Test hotkey: Cmd+Shift+H shows a hello alert
hs.hotkey.bind({"cmd", "shift"}, "H", function()
    hs.alert.show("Hammerspoon is working!")
end)


-- =============================================================
-- LINK MANAGER
-- Hotkey: Ctrl+Alt+L
-- =============================================================

local linkManagerWindow = nil
local previousWindow = nil
local linksFile = os.getenv("HOME") .. "/.hammerspoon/links.json"

-- Load links from JSON file
local function loadLinks()
    local f = io.open(linksFile, "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then return {} end
    return hs.json.decode(content) or {}
end

-- Save links to JSON file
local function saveLinks(links)
    local f = io.open(linksFile, "w")
    f:write(hs.json.encode(links, true))
    f:close()
end

-- Close link manager and refocus previous window
local function closeLinkManager()
    if linkManagerWindow then
        linkManagerWindow:delete()
        linkManagerWindow = nil
    end
    if previousWindow then
        hs.timer.doAfter(0.05, function()
            if previousWindow and previousWindow:application() then
                previousWindow:focus()
            end
            previousWindow = nil
        end)
    end
end

-- Build the HTML interface
local function buildHTML(linksJson)
    return [==[
<!DOCTYPE html>
<html>
<head>
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html {
        background: #e8e8ed;
    }
    body {
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", sans-serif;
        background: #f5f5f7;
        color: #1d1d1f;
        padding: 16px;
        height: 100vh;
        overflow: hidden;
        user-select: none;
        -webkit-user-select: none;
        font-size: 13px;
        line-height: 1.4;
        border: 1px solid #c7c7cc;
        border-top: none;
    }

    #searchBar {
        width: 100%;
        padding: 10px 14px;
        font-size: 14px;
        border: 1px solid #d2d2d7;
        border-radius: 10px;
        background: #ffffff;
        color: #1d1d1f;
        outline: none;
        box-shadow: 0 1px 3px rgba(0,0,0,0.06);
        transition: border-color 0.2s, box-shadow 0.2s;
    }
    #searchBar:focus {
        border-color: #007AFF;
        box-shadow: 0 0 0 3px rgba(0,122,255,0.15);
    }
    #searchBar.locked {
        border-color: #34C759;
        box-shadow: 0 0 0 3px rgba(52,199,89,0.15);
    }
    #searchBar::placeholder { color: #8e8e93; }

    .search-wrap { margin-bottom: 12px; }

    .view { display: none; }
    .view.active { display: flex; flex-direction: column; height: calc(100vh - 32px); }

    #resultsList {
        flex: 1;
        overflow-y: auto;
        -webkit-overflow-scrolling: touch;
    }
    #resultsList::-webkit-scrollbar { width: 6px; }
    #resultsList::-webkit-scrollbar-track { background: transparent; }
    #resultsList::-webkit-scrollbar-thumb { background: #c7c7cc; border-radius: 3px; }

    .link-item {
        display: flex;
        align-items: center;
        padding: 9px 12px;
        margin-bottom: 5px;
        border-radius: 10px;
        background: #ffffff;
        border: 1px solid #e5e5ea;
        transition: all 0.12s ease;
        box-shadow: 0 0.5px 2px rgba(0,0,0,0.04);
    }
    .link-item:hover {
        background: #f0f0f5;
        border-color: #d2d2d7;
        box-shadow: 0 1px 4px rgba(0,0,0,0.07);
    }

    .file-icon {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 28px;
        height: 28px;
        border-radius: 6px;
        font-size: 11px;
        font-weight: 700;
        margin-right: 10px;
        flex-shrink: 0;
        letter-spacing: -0.2px;
    }

    .link-num {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 22px;
        height: 22px;
        border-radius: 6px;
        background: #007AFF;
        color: white;
        font-size: 12px;
        font-weight: 600;
        margin-right: 10px;
        flex-shrink: 0;
        cursor: pointer;
    }

    .link-info {
        flex: 1;
        min-width: 0;
        cursor: pointer;
    }
    .link-name {
        font-size: 13px;
        font-weight: 500;
        color: #1d1d1f;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }
    .link-tags {
        font-size: 11px;
        color: #8e8e93;
        margin-top: 1px;
    }
    .link-types {
        font-size: 11px;
        color: #007AFF;
        margin-left: 8px;
        flex-shrink: 0;
    }
    .link-count {
        font-size: 10px;
        color: #aeaeb2;
        margin-left: 6px;
        flex-shrink: 0;
        font-weight: 500;
    }

    .edit-btn {
        cursor: pointer;
        margin-left: 8px;
        color: #aeaeb2;
        font-size: 13px;
        padding: 4px 6px;
        border-radius: 6px;
        transition: all 0.12s;
    }
    .edit-btn:hover { background: #e5e5ea; color: #1d1d1f; }

    .step-header {
        font-size: 13px;
        color: #8e8e93;
        margin-bottom: 10px;
        padding-bottom: 10px;
        border-bottom: 1px solid #e5e5ea;
    }
    .step-header strong { color: #1d1d1f; font-size: 15px; }

    .option-item {
        display: flex;
        align-items: center;
        padding: 10px 12px;
        margin-bottom: 5px;
        border-radius: 10px;
        background: #ffffff;
        border: 1px solid #e5e5ea;
        cursor: pointer;
        transition: all 0.12s ease;
        box-shadow: 0 0.5px 2px rgba(0,0,0,0.04);
    }
    .option-item:hover {
        background: #f0f0f5;
        border-color: #d2d2d7;
    }

    .hint {
        font-size: 11px;
        color: #8e8e93;
        text-align: center;
        padding: 8px 0 2px;
        flex-shrink: 0;
    }
    .hint kbd {
        display: inline-block;
        background: #e5e5ea;
        padding: 1px 6px;
        border-radius: 4px;
        font-family: -apple-system, sans-serif;
        font-size: 11px;
        color: #636366;
        border: 1px solid #d2d2d7;
    }

    /* Add/Edit Form */
    .form-group { margin-bottom: 10px; }
    .form-group label {
        display: block;
        font-size: 12px;
        color: #8e8e93;
        margin-bottom: 4px;
        font-weight: 500;
    }
    .form-group input {
        width: 100%;
        padding: 8px 10px;
        font-size: 13px;
        border: 1px solid #d2d2d7;
        border-radius: 8px;
        background: #ffffff;
        color: #1d1d1f;
        outline: none;
        transition: border-color 0.2s, box-shadow 0.2s;
    }
    .form-group input:focus {
        border-color: #007AFF;
        box-shadow: 0 0 0 3px rgba(0,122,255,0.15);
    }
    .form-group input::placeholder { color: #c7c7cc; }

    .form-buttons {
        display: flex;
        gap: 8px;
        margin-top: 14px;
        flex-shrink: 0;
    }
    .btn {
        padding: 8px 16px;
        border-radius: 8px;
        border: none;
        font-size: 13px;
        cursor: pointer;
        font-weight: 500;
        transition: all 0.12s;
    }
    .btn-primary { background: #007AFF; color: white; }
    .btn-primary:hover { background: #0066d6; }
    .btn-secondary { background: #e5e5ea; color: #1d1d1f; }
    .btn-secondary:hover { background: #d2d2d7; }
    .btn-danger { background: #FF3B30; color: white; }
    .btn-danger:hover { background: #d63029; }

    .empty-state {
        text-align: center;
        padding: 40px 20px;
        color: #8e8e93;
    }
    .empty-state .icon { font-size: 28px; margin-bottom: 8px; }

    .add-view-scroll {
        flex: 1;
        overflow-y: auto;
    }

    /* Counter editor */
    .counter-row {
        display: flex;
        align-items: center;
        gap: 6px;
        margin-bottom: 12px;
        padding: 8px 10px;
        background: #ffffff;
        border: 1px solid #e5e5ea;
        border-radius: 10px;
    }
    .counter-row label {
        font-size: 12px;
        color: #8e8e93;
        font-weight: 500;
        margin-right: 4px;
        white-space: nowrap;
    }
    .counter-input {
        width: 56px;
        padding: 4px 6px;
        font-size: 13px;
        text-align: center;
        border: 1px solid #d2d2d7;
        border-radius: 6px;
        background: #f5f5f7;
        color: #1d1d1f;
        outline: none;
        -moz-appearance: textfield;
    }
    .counter-input::-webkit-inner-spin-button,
    .counter-input::-webkit-outer-spin-button { -webkit-appearance: none; margin: 0; }
    .counter-input:focus { border-color: #007AFF; box-shadow: 0 0 0 2px rgba(0,122,255,0.12); }
    .counter-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 26px;
        height: 26px;
        border-radius: 6px;
        border: 1px solid #d2d2d7;
        background: #f5f5f7;
        color: #1d1d1f;
        font-size: 15px;
        cursor: pointer;
        transition: all 0.1s;
        font-weight: 500;
        line-height: 1;
    }
    .counter-btn:hover { background: #e5e5ea; }
    .counter-clear {
        font-size: 11px;
        color: #FF3B30;
        cursor: pointer;
        margin-left: 4px;
        font-weight: 500;
        padding: 3px 8px;
        border-radius: 4px;
        transition: background 0.1s;
    }
    .counter-clear:hover { background: #FDE8E7; }

    /* Help button */
    .help-btn {
        width: 22px;
        height: 22px;
        border-radius: 50%;
        background: #e5e5ea;
        border: 1px solid #d2d2d7;
        color: #8e8e93;
        font-size: 13px;
        font-weight: 600;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        cursor: pointer;
        transition: all 0.12s;
        z-index: 10;
        font-family: -apple-system, sans-serif;
        flex-shrink: 0;
    }
    .help-btn:hover { background: #d2d2d7; color: #636366; }

    /* Help overlay */
    .help-overlay {
        display: none;
        position: fixed;
        top: 0; left: 0; right: 0; bottom: 0;
        background: rgba(0,0,0,0.25);
        z-index: 100;
        align-items: center;
        justify-content: center;
    }
    .help-overlay.active { display: flex; }
    .help-card {
        background: #ffffff;
        border-radius: 14px;
        padding: 22px 24px;
        width: 500px;
        max-height: 420px;
        overflow-y: auto;
        box-shadow: 0 8px 32px rgba(0,0,0,0.18);
        border: 1px solid #d2d2d7;
    }
    .help-card h2 {
        font-size: 17px;
        font-weight: 600;
        color: #1d1d1f;
        margin-bottom: 6px;
    }
    .help-card .help-subtitle {
        font-size: 12px;
        color: #8e8e93;
        margin-bottom: 14px;
        line-height: 1.5;
    }
    .help-card h3 {
        font-size: 13px;
        font-weight: 600;
        color: #1d1d1f;
        margin: 12px 0 4px;
    }
    .help-card p {
        font-size: 12px;
        color: #48484a;
        line-height: 1.55;
        margin-bottom: 6px;
    }
    .help-card kbd {
        display: inline-block;
        background: #f2f2f7;
        padding: 1px 5px;
        border-radius: 4px;
        font-family: -apple-system, sans-serif;
        font-size: 11px;
        color: #636366;
        border: 1px solid #d2d2d7;
    }
    .help-close {
        float: right;
        font-size: 12px;
        color: #007AFF;
        cursor: pointer;
        font-weight: 500;
        padding: 2px 6px;
        border-radius: 4px;
    }
    .help-close:hover { background: #E8F0FE; }
</style>
</head>
<body>

<!-- SEARCH VIEW -->
<div id="searchView" class="view active">
    <div class="search-wrap">
        <input type="text" id="searchBar" placeholder="Search links..." autofocus>
    </div>
    <div id="resultsList"></div>
    <div class="hint" style="display:flex; align-items:center; justify-content:center;">
        <span style="flex:1; text-align:center;">
            <kbd>Enter</kbd> lock search, then <kbd>Enter</kbd> or <kbd>1-9</kbd> to pick &nbsp;&middot;&nbsp; <kbd>Tab</kbd> add new &nbsp;&middot;&nbsp; <kbd>Esc</kbd> close
        </span>
        <span class="help-btn" onclick="toggleHelp()" title="Help">?</span>
    </div>
</div>

<!-- TYPE SELECTION VIEW -->
<div id="typeView" class="view">
    <div class="step-header" id="typeHeader"></div>
    <div id="typeList" style="flex:1; overflow-y:auto;"></div>
    <div class="hint">
        <kbd>Enter</kbd> pick first &nbsp;&middot;&nbsp; <kbd>1-9</kbd> pick by number &nbsp;&middot;&nbsp; <kbd>Esc</kbd> back
    </div>
</div>

<!-- FORMAT SELECTION VIEW -->
<div id="formatView" class="view">
    <div class="step-header" id="formatHeader"></div>
    <div id="formatList">
        <div class="option-item" onclick="selectFormat('raw')">
            <span class="link-num">1</span>
            <span class="link-name">Raw URL</span>
        </div>
        <div class="option-item" onclick="selectFormat('linked')">
            <span class="link-num">2</span>
            <span class="link-name">Linked Text (clickable hyperlink)</span>
        </div>
    </div>
    <div class="hint">
        <kbd>Enter</kbd> use preferred &nbsp;&middot;&nbsp; <kbd>1</kbd> raw URL &nbsp;&middot;&nbsp; <kbd>2</kbd> linked text &nbsp;&middot;&nbsp; <kbd>Esc</kbd> back
    </div>
</div>

<!-- ADD/EDIT VIEW -->
<div id="addView" class="view">
    <div class="step-header"><strong id="addTitle">Add New Link</strong></div>
    <div class="add-view-scroll">
        <div class="form-group">
            <label>Name / Filename</label>
            <input type="text" id="addName" placeholder="e.g. Project Requirements.docx">
        </div>
        <div class="form-group">
            <label>Tags (comma separated)</label>
            <input type="text" id="addTags" placeholder="e.g. project, docs, planning">
        </div>
        <div id="linkFields"></div>
        <div style="margin-bottom:10px;">
            <span class="btn btn-secondary" onclick="addLinkField()" style="font-size:12px; padding:4px 10px;">+ Add Link Type</span>
        </div>
        <div class="counter-row" id="counterRow" style="display:none;">
            <label>Usage count</label>
            <span class="counter-btn" onclick="adjustCount(-1)">&minus;</span>
            <input type="number" class="counter-input" id="countInput" value="0" min="0">
            <span class="counter-btn" onclick="adjustCount(1)">+</span>
            <span class="counter-clear" onclick="clearCount()">&times; Reset</span>
        </div>
    </div>
    <div class="form-buttons">
        <button class="btn btn-primary" onclick="saveLink()">Save</button>
        <button class="btn btn-secondary" onclick="cancelAdd()">Cancel</button>
        <button class="btn btn-danger" id="deleteBtn" onclick="deleteLink()" style="display:none; margin-left:auto;">Delete</button>
    </div>
</div>

<!-- HELP OVERLAY -->
<div id="helpOverlay" class="help-overlay" onclick="if(event.target===this)toggleHelp()">
    <div class="help-card">
        <span class="help-close" onclick="toggleHelp()">Done</span>
        <h2>Link Manager</h2>
        <div class="help-subtitle">A keyboard-driven tool for saving, organizing, and quickly copying links you use often. Over time, your most-used links rise to the top, so grabbing them gets faster the more you use it.</div>

        <h3>Quick Copy (the fast way)</h3>
        <p>Type a few characters to filter, then press <kbd>Enter</kbd> to lock your search. Press <kbd>Enter</kbd> again to grab the top result instantly. If the link has multiple types, one more <kbd>Enter</kbd> selects the top type and copies it. That's it: type, <kbd>Enter</kbd>, <kbd>Enter</kbd> &mdash; done.</p>

        <h3>Browse &amp; Pick</h3>
        <p>After locking search with <kbd>Enter</kbd>, press a number <kbd>1</kbd>&ndash;<kbd>9</kbd> to pick a specific link. If it has multiple types (e.g. View, Edit), pick a type the same way. Then choose <kbd>1</kbd> for the raw URL or <kbd>2</kbd> for a clickable hyperlink.</p>

        <h3>Copy Formats</h3>
        <p><strong>Raw URL</strong> pastes the plain URL. <strong>Linked Text</strong> pastes a clickable hyperlink (the link name becomes the clickable text). Linked Text works in Slack, Word, Outlook, and most rich-text fields.</p>

        <h3>Smart Priority</h3>
        <p>Every time you copy a link, its usage count goes up. Links you use most sort to the top of results automatically. The same applies to link types and copy formats &mdash; your preferred choices become the default over time.</p>

        <h3>Adding &amp; Editing Links</h3>
        <p>Press <kbd>Tab</kbd> to add a new link. Give it a name (include the file extension like .docx or .pptx for automatic file-type icons), add optional tags for easier searching, and add one or more link types with their URLs. Click the pencil icon on any link to edit it, adjust its usage count, or delete it. Press <kbd>&#8984;Enter</kbd> to quick-save.</p>

        <h3>Keyboard Shortcuts</h3>
        <p><kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>L</kbd> &mdash; Open / close Link Manager<br>
        <kbd>Enter</kbd> &mdash; Lock search, then auto-select top result<br>
        <kbd>1</kbd>&ndash;<kbd>9</kbd> &mdash; Pick a numbered item<br>
        <kbd>Tab</kbd> &mdash; Add a new link<br>
        <kbd>Esc</kbd> &mdash; Go back one step, or close<br>
        <kbd>?</kbd> &mdash; Toggle this help screen</p>
    </div>
</div>

<script>
    // ── State ──
    var links = ]==] .. linksJson .. [==[;
    var filteredLinks = [];
    var currentState = 'search';
    var selectedLink = null;
    var selectedType = null;
    var selectedUrl = null;
    var editIndex = null;
    var linkFieldCount = 0;
    var searchLocked = false;
    var sortedTypes = [];

    // ── File Type Detection ──
    // Checks the link NAME for a file extension first, then falls back to URL patterns
    function detectExtension(name) {
        if (!name) return null;
        var m = name.match(/\.(pptx?|docx?|xlsx?|pdf|csv|txt|one|vsdx?|mpp)$/i);
        return m ? m[1].toLowerCase() : null;
    }

    function iconFromExtension(ext) {
        if (!ext) return null;
        if (ext === 'ppt' || ext === 'pptx') return {letter:'P', color:'#D04423', bg:'#FDEDEA'};
        if (ext === 'doc' || ext === 'docx') return {letter:'W', color:'#185ABD', bg:'#DCEAF8'};
        if (ext === 'xls' || ext === 'xlsx') return {letter:'X', color:'#217346', bg:'#E6F2EB'};
        if (ext === 'pdf')  return {letter:'PDF', color:'#E4362D', bg:'#FDE8E7'};
        if (ext === 'csv')  return {letter:'CSV', color:'#217346', bg:'#E6F2EB'};
        if (ext === 'txt')  return {letter:'TXT', color:'#8E8E93', bg:'#F2F2F7'};
        if (ext === 'one')  return {letter:'N', color:'#7719AA', bg:'#F2E6F8'};
        if (ext === 'vsd' || ext === 'vsdx') return {letter:'V', color:'#3955A3', bg:'#E8EDF7'};
        if (ext === 'mpp')  return {letter:'MP', color:'#31752F', bg:'#E6F2EB'};
        return null;
    }

    function getFileIcon(name, linksObj) {
        // 1. Check the link name for a file extension
        var ext = detectExtension(name);
        var icon = iconFromExtension(ext);
        if (icon) return icon;

        // 2. Fall back to URL pattern matching
        var urls = Object.values(linksObj || {}).join(' ').toLowerCase();
        if (urls.match(/\.pptx?(\b|$|[?#])/) || urls.match(/\/presentation/) || urls.match(/slides\.google/))
            return {letter:'P', color:'#D04423', bg:'#FDEDEA'};
        if (urls.match(/\.docx?(\b|$|[?#])/) || urls.match(/docs\.google\.com\/document/))
            return {letter:'W', color:'#185ABD', bg:'#DCEAF8'};
        if (urls.match(/\.xlsx?(\b|$|[?#])/) || urls.match(/sheets\.google/) || urls.match(/\/spreadsheet/))
            return {letter:'X', color:'#217346', bg:'#E6F2EB'};
        if (urls.match(/\.pdf(\b|$|[?#])/))
            return {letter:'PDF', color:'#E4362D', bg:'#FDE8E7'};
        if (urls.match(/\.csv(\b|$|[?#])/))
            return {letter:'CSV', color:'#217346', bg:'#E6F2EB'};
        if (urls.match(/jira/) || urls.match(/atlassian.*browse/))
            return {letter:'J', color:'#0065FF', bg:'#DEEBFF'};
        if (urls.match(/confluence/) || urls.match(/atlassian.*wiki/))
            return {letter:'C', color:'#5243AA', bg:'#EAE6FF'};
        if (urls.match(/sharepoint/))
            return {letter:'S', color:'#03787C', bg:'#DFF0F0'};
        if (urls.match(/onenote/))
            return {letter:'N', color:'#7719AA', bg:'#F2E6F8'};
        if (urls.match(/drive\.google/) || urls.match(/docs\.google/))
            return {letter:'G', color:'#4285F4', bg:'#E8F0FE'};
        if (urls.match(/teams\.microsoft/))
            return {letter:'T', color:'#6264A7', bg:'#EEEFFA'};
        if (urls.match(/github\.com/))
            return {letter:'GH', color:'#24292f', bg:'#eaeef2'};
        if (urls.match(/figma\.com/))
            return {letter:'F', color:'#A259FF', bg:'#F3EAFE'};
        if (urls.match(/miro\.com/))
            return {letter:'M', color:'#FFD02F', bg:'#FFF8E1'};
        return {letter:'\u2197', color:'#8E8E93', bg:'#F2F2F7'};
    }

    // ── Views ──
    function showView(name) {
        document.querySelectorAll('.view').forEach(function(v) { v.classList.remove('active'); });
        document.getElementById(name + 'View').classList.add('active');
        currentState = name;
    }

    // ── Search & Filter ──
    function renderResults() {
        var query = document.getElementById('searchBar').value.toLowerCase().trim();

        if (links.length === 0 && query === '') {
            document.getElementById('resultsList').innerHTML =
                '<div class="empty-state"><div class="icon">\u{1F517}</div>No links yet.<br>Press <kbd>Tab</kbd> to add your first link.</div>';
            filteredLinks = [];
            return;
        }

        var matched = links.filter(function(link) {
            if (query === '') return true;
            var searchable = (link.name + ' ' + (link.tags || '')).toLowerCase();
            return query.split(/\s+/).every(function(word) { return searchable.indexOf(word) !== -1; });
        });

        // Sort by copyCount descending (priority)
        matched.sort(function(a, b) {
            return (b.copyCount || 0) - (a.copyCount || 0);
        });

        filteredLinks = matched;

        if (filteredLinks.length === 0) {
            document.getElementById('resultsList').innerHTML =
                '<div class="empty-state" style="padding:30px;">No matches found</div>';
            return;
        }

        var html = '';
        filteredLinks.forEach(function(link, i) {
            if (i >= 9) return;
            var typeNames = Object.keys(link.links || {}).join(', ');
            var icon = getFileIcon(link.name, link.links);
            var count = link.copyCount || 0;
            var countHtml = count > 0 ? '<span class="link-count">' + count + '\u00d7</span>' : '';
            var iconFontSize = icon.letter.length > 2 ? '9px' : (icon.letter.length > 1 ? '10px' : '11px');

            html += '<div class="link-item">' +
                '<span class="link-num" onclick="selectLink(' + i + ')">' + (i + 1) + '</span>' +
                '<span class="file-icon" style="background:' + icon.bg + '; color:' + icon.color + '; font-size:' + iconFontSize + ';">' + icon.letter + '</span>' +
                '<div class="link-info" onclick="selectLink(' + i + ')">' +
                    '<div class="link-name">' + escHtml(link.name) + '</div>' +
                    (link.tags ? '<div class="link-tags">' + escHtml(link.tags) + '</div>' : '') +
                '</div>' +
                '<div class="link-types">' + escHtml(typeNames) + '</div>' +
                countHtml +
                '<span class="edit-btn" onclick="editByFilterIndex(' + i + ')" title="Edit">\u270E</span>' +
            '</div>';
        });
        document.getElementById('resultsList').innerHTML = html;
    }

    function escHtml(str) {
        if (!str) return '';
        return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }

    document.getElementById('searchBar').addEventListener('input', function() {
        if (searchLocked) {
            searchLocked = false;
            document.getElementById('searchBar').classList.remove('locked');
        }
        renderResults();
    });

    // ── Edit by filtered index ──
    function editByFilterIndex(i) {
        var link = filteredLinks[i];
        var globalIndex = links.indexOf(link);
        showAddView(globalIndex);
    }

    // ── Preferred format for a link (linked text default) ──
    function getPreferredFormat(link) {
        var fc = link.formatCounts || {};
        var rawCount = fc.raw || 0;
        var linkedCount = fc.linked || 0;
        if (rawCount > linkedCount) return 'raw';
        return 'linked';
    }

    // ── Sort types by usage count ──
    function getSortedTypes(link) {
        var types = Object.keys(link.links || {});
        var tc = link.typeCounts || {};
        types.sort(function(a, b) {
            return (tc[b] || 0) - (tc[a] || 0);
        });
        return types;
    }

    // ── Render type list (reused by selectLink and autoSelectLink) ──
    function renderTypeView(link, types) {
        document.getElementById('typeHeader').innerHTML =
            'Select link type for: <strong>' + escHtml(link.name) + '</strong>';
        var tc = link.typeCounts || {};
        var html = '';
        types.forEach(function(type, i) {
            var count = tc[type] || 0;
            var countHtml = count > 0 ? ' <span style="color:#aeaeb2; font-size:10px;">(' + count + ')</span>' : '';
            html += '<div class="option-item" onclick="selectType(' + i + ')">' +
                '<span class="link-num">' + (i + 1) + '</span>' +
                '<div class="link-info">' +
                    '<div class="link-name">' + escHtml(type) + countHtml + '</div>' +
                    '<div class="link-tags" style="word-break:break-all;">' + escHtml(link.links[type]) + '</div>' +
                '</div>' +
            '</div>';
        });
        document.getElementById('typeList').innerHTML = html;
        showView('type');
    }

    // ── Link Selection (via number keys / click) ──
    function selectLink(index) {
        selectedLink = filteredLinks[index];
        if (!selectedLink) return;
        sortedTypes = getSortedTypes(selectedLink);
        if (sortedTypes.length === 0) return;

        if (sortedTypes.length === 1) {
            selectedType = sortedTypes[0];
            selectedUrl = selectedLink.links[selectedType];
            showFormatView();
            return;
        }
        renderTypeView(selectedLink, sortedTypes);
    }

    // ── Auto-select: Enter fast-flow (picks #1, copies with preferred format) ──
    function autoSelectLink() {
        if (filteredLinks.length === 0) return;
        selectedLink = filteredLinks[0];
        sortedTypes = getSortedTypes(selectedLink);
        if (sortedTypes.length === 0) return;

        if (sortedTypes.length === 1) {
            selectedType = sortedTypes[0];
            selectedUrl = selectedLink.links[selectedType];
            doCopy(getPreferredFormat(selectedLink));
            return;
        }
        // Multiple types: show type view, next Enter auto-selects #1
        renderTypeView(selectedLink, sortedTypes);
    }

    function autoSelectType() {
        if (sortedTypes.length === 0) return;
        selectedType = sortedTypes[0];
        selectedUrl = selectedLink.links[selectedType];
        doCopy(getPreferredFormat(selectedLink));
    }

    // ── Type Selection ──
    function selectType(index) {
        if (index >= sortedTypes.length) return;
        selectedType = sortedTypes[index];
        selectedUrl = selectedLink.links[selectedType];
        showFormatView();
    }

    function showFormatView() {
        document.getElementById('formatHeader').innerHTML =
            '<strong>' + escHtml(selectedLink.name) + '</strong> \u2192 ' + escHtml(selectedType);
        showView('format');
    }

    // ── Copy ──
    function doCopy(format) {
        window.webkit.messageHandlers.linkManager.postMessage({
            action: 'copy',
            name: selectedLink.name,
            url: selectedUrl,
            linkType: selectedType,
            format: format
        });
    }

    function selectFormat(format) {
        doCopy(format);
    }

    // ── Add / Edit Form ──
    function showAddView(index) {
        editIndex = (index !== undefined && index !== null) ? index : null;
        linkFieldCount = 0;
        document.getElementById('linkFields').innerHTML = '';

        if (editIndex !== null) {
            var link = links[editIndex];
            document.getElementById('addTitle').textContent = 'Edit Link';
            document.getElementById('addName').value = link.name || '';
            document.getElementById('addTags').value = link.tags || '';
            document.getElementById('deleteBtn').style.display = 'inline-block';

            // Show and populate the usage counter
            document.getElementById('counterRow').style.display = 'flex';
            document.getElementById('countInput').value = link.copyCount || 0;

            var types = Object.keys(link.links || {});
            types.forEach(function(type) {
                addLinkField(type, link.links[type]);
            });
            if (types.length === 0) addLinkField();
        } else {
            document.getElementById('addTitle').textContent = 'Add New Link';
            document.getElementById('addName').value = '';
            document.getElementById('addTags').value = '';
            document.getElementById('deleteBtn').style.display = 'none';

            // Hide counter for new links
            document.getElementById('counterRow').style.display = 'none';
            document.getElementById('countInput').value = 0;

            addLinkField('View', '');
            addLinkField('Edit', '');
        }

        showView('add');
        document.getElementById('addName').focus();
    }

    function addLinkField(typeName, urlVal) {
        linkFieldCount++;
        var id = linkFieldCount;
        var html = '<div class="form-group" id="linkField' + id + '" style="display:flex; gap:8px; align-items:flex-end;">' +
            '<div style="width:28%;">' +
                '<label>Type</label>' +
                '<input type="text" id="linkType' + id + '" placeholder="e.g. View" value="' + escAttr(typeName || '') + '">' +
            '</div>' +
            '<div style="width:65%;">' +
                '<label>URL</label>' +
                '<input type="text" id="linkUrl' + id + '" placeholder="https://..." value="' + escAttr(urlVal || '') + '">' +
            '</div>' +
            '<div style="width:7%; display:flex; align-items:center; justify-content:center; padding-bottom:2px;">' +
                '<span onclick="removeLinkField(' + id + ')" style="cursor:pointer; color:#FF3B30; font-size:18px; line-height:1;">\u00d7</span>' +
            '</div>' +
        '</div>';
        document.getElementById('linkFields').insertAdjacentHTML('beforeend', html);
    }

    function removeLinkField(id) {
        var el = document.getElementById('linkField' + id);
        if (el) el.remove();
    }

    function escAttr(str) {
        if (!str) return '';
        return str.replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function saveLink() {
        var name = document.getElementById('addName').value.trim();
        if (!name) { document.getElementById('addName').focus(); return; }

        var tags = document.getElementById('addTags').value.trim();
        var linksObj = {};

        document.querySelectorAll('[id^="linkField"]').forEach(function(field) {
            var id = field.id.replace('linkField', '');
            var typeEl = document.getElementById('linkType' + id);
            var urlEl = document.getElementById('linkUrl' + id);
            if (typeEl && urlEl && typeEl.value.trim() && urlEl.value.trim()) {
                linksObj[typeEl.value.trim()] = urlEl.value.trim();
            }
        });

        // Preserve existing counts when editing, but use the manual counter value
        var linkData = { name: name, tags: tags, links: linksObj };
        if (editIndex !== null && links[editIndex]) {
            linkData.copyCount = Math.max(0, parseInt(document.getElementById('countInput').value) || 0);
            linkData.typeCounts = links[editIndex].typeCounts || {};
            linkData.formatCounts = links[editIndex].formatCounts || {};
        }

        window.webkit.messageHandlers.linkManager.postMessage({
            action: 'save',
            link: linkData,
            editIndex: editIndex !== null ? editIndex + 1 : null
        });
    }

    function deleteLink() {
        if (editIndex === null) return;
        if (!confirm('Delete "' + links[editIndex].name + '"?')) return;
        window.webkit.messageHandlers.linkManager.postMessage({
            action: 'delete',
            index: editIndex + 1
        });
    }

    function cancelAdd() {
        showView('search');
        document.getElementById('searchBar').focus();
    }

    // ── Counter Controls ──
    function adjustCount(delta) {
        var input = document.getElementById('countInput');
        var val = parseInt(input.value) || 0;
        val = Math.max(0, val + delta);
        input.value = val;
    }
    function clearCount() {
        document.getElementById('countInput').value = 0;
    }

    // ── Help Overlay ──
    function toggleHelp() {
        var overlay = document.getElementById('helpOverlay');
        overlay.classList.toggle('active');
    }

    // ── Keyboard Handler ──
    document.addEventListener('keydown', function(e) {
        var sb = document.getElementById('searchBar');
        var helpOpen = document.getElementById('helpOverlay').classList.contains('active');

        // Close help with Esc or ? toggle
        if (helpOpen) {
            if (e.key === 'Escape' || e.key === '?') {
                e.preventDefault();
                toggleHelp();
            }
            return;
        }

        // ? to open help (only when not in a text input)
        if (e.key === '?' && document.activeElement.tagName !== 'INPUT') {
            e.preventDefault();
            toggleHelp();
            return;
        }

        // ═══ SEARCH STATE ═══
        if (currentState === 'search') {

            // Enter in search bar (not locked): lock search
            if (e.key === 'Enter' && document.activeElement === sb && !searchLocked) {
                e.preventDefault();
                searchLocked = true;
                sb.classList.add('locked');
                sb.blur();
                return;
            }

            // Enter when locked: auto-select #1
            if (e.key === 'Enter' && searchLocked) {
                e.preventDefault();
                autoSelectLink();
                return;
            }

            // Down arrow: lock search
            if (e.key === 'ArrowDown' && document.activeElement === sb) {
                e.preventDefault();
                searchLocked = true;
                sb.classList.add('locked');
                sb.blur();
                return;
            }

            // Letter key when blurred: unlock and refocus
            if (document.activeElement !== sb && e.key.length === 1 && e.key.match(/[a-z]/i) && !e.ctrlKey && !e.metaKey) {
                searchLocked = false;
                sb.classList.remove('locked');
                sb.focus();
                return;
            }

            // Tab: add new
            if (e.key === 'Tab') {
                e.preventDefault();
                showAddView();
                return;
            }

            // Esc: close
            if (e.key === 'Escape') {
                e.preventDefault();
                window.webkit.messageHandlers.linkManager.postMessage({ action: 'close' });
                return;
            }

            // Number keys when locked
            if (e.key >= '1' && e.key <= '9' && searchLocked) {
                e.preventDefault();
                var num = parseInt(e.key) - 1;
                if (filteredLinks[num]) selectLink(num);
                return;
            }
            return;
        }

        // ═══ TYPE STATE ═══
        if (currentState === 'type') {
            if (e.key === 'Enter') {
                e.preventDefault();
                autoSelectType();
                return;
            }
            if (e.key >= '1' && e.key <= '9') {
                e.preventDefault();
                selectType(parseInt(e.key) - 1);
                return;
            }
            if (e.key === 'Escape') {
                e.preventDefault();
                searchLocked = false;
                sb.classList.remove('locked');
                showView('search');
                sb.focus();
                return;
            }
            return;
        }

        // ═══ FORMAT STATE ═══
        if (currentState === 'format') {
            if (e.key === 'Enter') {
                e.preventDefault();
                selectFormat(getPreferredFormat(selectedLink));
                return;
            }
            if (e.key === '1') { e.preventDefault(); selectFormat('raw'); return; }
            if (e.key === '2') { e.preventDefault(); selectFormat('linked'); return; }
            if (e.key === 'Escape') {
                e.preventDefault();
                if (sortedTypes.length > 1) {
                    showView('type');
                } else {
                    searchLocked = false;
                    sb.classList.remove('locked');
                    showView('search');
                    sb.focus();
                }
                return;
            }
            return;
        }

        // ═══ ADD STATE ═══
        if (currentState === 'add') {
            if (e.key === 'Escape') {
                e.preventDefault();
                cancelAdd();
                return;
            }
            // Cmd+Enter to save
            if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
                e.preventDefault();
                saveLink();
                return;
            }
            return;
        }
    });

    // ── Init ──
    renderResults();
    document.getElementById('searchBar').focus();
</script>
</body>
</html>
]==];
end

-- Open/close the link manager
local function openLinkManager()
    -- Safety: if window ref exists but actual window is gone, clean up
    if linkManagerWindow then
        local ok, hswin = pcall(function() return linkManagerWindow:hswindow() end)
        if not ok or not hswin then
            linkManagerWindow = nil
            previousWindow = nil
        else
            closeLinkManager()
            return
        end
    end

    -- Capture current focused window for later refocus
    previousWindow = hs.window.focusedWindow()

    local links = loadLinks()
    local linksJson = hs.json.encode(links) or "[]"

    local uc = hs.webview.usercontent.new("linkManager")
    uc:setCallback(function(msg)
        local body = msg.body

        if body.action == "copy" then
            local linkName = body.name
            local url = body.url
            local linkType = body.linkType
            local format = body.format

            -- Increment counters in the stored data
            local allLinks = loadLinks()
            for i, link in ipairs(allLinks) do
                if link.name == linkName then
                    link.copyCount = (link.copyCount or 0) + 1
                    if not link.typeCounts then link.typeCounts = {} end
                    link.typeCounts[linkType] = (link.typeCounts[linkType] or 0) + 1
                    if not link.formatCounts then link.formatCounts = {} end
                    link.formatCounts[format] = (link.formatCounts[format] or 0) + 1
                    allLinks[i] = link
                    break
                end
            end
            saveLinks(allLinks)

            -- Copy to clipboard
            if format == "raw" then
                hs.pasteboard.setContents(url)
                hs.alert.show("Copied raw URL\n" .. linkType .. " -> " .. linkName, nil, nil, 1.5)
            else
                -- Rich text: HTML + plain text fallback for Slack, Word, etc.
                local htmlContent = '<a href="' .. url .. '">' .. linkName .. '</a>'
                local hexHtml = htmlContent:gsub('.', function(c)
                    return string.format('%02X', string.byte(c))
                end)
                local hexText = linkName:gsub('.', function(c)
                    return string.format('%02X', string.byte(c))
                end)
                local script = 'set the clipboard to {' ..
                    '«class HTML»:«data HTML' .. hexHtml .. '», ' ..
                    '«class utf8»:«data utf8' .. hexText .. '»}'
                hs.osascript.applescript(script)
                hs.alert.show("Copied linked text\n" .. linkType .. " -> " .. linkName, nil, nil, 1.5)
            end

            closeLinkManager()

        elseif body.action == "save" then
            local allLinks = loadLinks()
            if body.editIndex then
                allLinks[body.editIndex] = body.link
            else
                table.insert(allLinks, body.link)
            end
            saveLinks(allLinks)
            -- Reopen to reflect changes (save previousWindow ref)
            local savedPrev = previousWindow
            closeLinkManager()
            hs.timer.doAfter(0.15, function()
                previousWindow = savedPrev
                openLinkManager()
            end)

        elseif body.action == "delete" then
            local allLinks = loadLinks()
            table.remove(allLinks, body.index)
            saveLinks(allLinks)
            local savedPrev = previousWindow
            closeLinkManager()
            hs.timer.doAfter(0.15, function()
                previousWindow = savedPrev
                openLinkManager()
            end)

        elseif body.action == "close" then
            closeLinkManager()
        end
    end)

    local screen = hs.screen.mainScreen():frame()
    local w, h = 560, 480
    local rect = hs.geometry.rect((screen.w - w) / 2, (screen.h - h) / 2, w, h)

    linkManagerWindow = hs.webview.new(rect, {}, uc)
        :windowStyle({"titled", "closable"})
        :html(buildHTML(linksJson))
        :allowTextEntry(true)
        :level(hs.drawing.windowLevels.floating)
        :windowTitle("Link Manager")
        :shadow(true)
        :show()
        :bringToFront(true)

    -- Handle user closing via the title bar X button
    linkManagerWindow:windowCallback(function(action)
        if action == "closing" then
            linkManagerWindow = nil
            if previousWindow and previousWindow:application() then
                previousWindow:focus()
            end
            previousWindow = nil
        end
    end)

    -- Give the webview keyboard focus reliably
    hs.timer.doAfter(0.05, function()
        if linkManagerWindow then
            local ok, hswin = pcall(function() return linkManagerWindow:hswindow() end)
            if ok and hswin then
                hswin:focus()
            end
        end
    end)
end

-- Bind hotkey
hs.hotkey.bind({"ctrl", "alt"}, "L", openLinkManager)
