// threshold_table_widget.js
// v-final: single-source from core widgets, dynamic min node height,
// DOM-based table, polling for widget-changes (500ms).
// Import path absolute.

import { app } from "/scripts/app.js";

app.registerExtension({
  name: "comfyui_stereoscopic.grade_variant_widget",
  async init(appInstance) {

    // ---------------- constants ----------------
    const ROW_GAP = 6;
    const ADD_BTN_H = 26;
    const BASE_H = 44;
    const ROW_H = 27;
    const EXTRA_BOTTOM = 104;
    const POLL_MS = 500;

    // ---------------- helpers ----------------
    function isTarget(node) {
      try { return node && ( node.type === "GradeVariant" ); }
      catch (e) { return false; }
    }

    function findWidget(node, name) {
      if (!node.widgets) return null;
      return node.widgets.find(w => w.name === name) || null;
    }

    // Parse a widget (might be JSON-string or already array)
    function parseWidgetValue(v) {
      if (v === undefined || v === null) return [];
      if (Array.isArray(v)) return v.slice();
      if (typeof v === "string") {
        try {
          const p = JSON.parse(v);
          if (Array.isArray(p)) return p.slice();
        } catch (e) { /* not JSON */ }
      }
      return [];
    }

    // Read authoritative arrays from core widget inputs "weights" and "texts"
    function readFromCoreWidgets(node) {
      // prefer reading from widget values (text widgets above the table).
      const wT = findWidget(node, "weights");
      const wX = findWidget(node, "texts");

      let weights = [], texts = [];
      if (wT && wT.value !== undefined) weights = parseWidgetValue(wT.value);
      if (wX && wX.value !== undefined) texts = parseWidgetValue(wX.value);

      // Coerce types and make equal length
      weights = weights.map(v => {
        const n = Number(v);
        return Number.isFinite(n) ? n : 0.0;
      });
      texts = texts.map(v => (v == null ? "" : String(v)));

      const n = Math.min(weights.length, texts.length);
      weights = weights.slice(0, n);
      texts = texts.slice(0, n);

      return { weights, texts };
    }

    // Write arrays back to core widgets + properties (two-way sync)
    function writeToCoreWidgets(node, weights, texts) {
      // ensure arrays
      weights = Array.from(weights || []);
      texts = Array.from(texts || []);
      const n = Math.min(weights.length, texts.length);
      weights = weights.slice(0, n);
      texts = texts.slice(0, n);

      // write to widgets if present, else create them as text widgets
      try {
        let wT = findWidget(node, "weights");
        let wX = findWidget(node, "texts");

        if (!wT) wT = node.addWidget("text", "weights", JSON.stringify(weights), () => {});
        if (!wX) wX = node.addWidget("text", "texts", JSON.stringify(texts), () => {});

        wT.value = JSON.stringify(weights);
        wX.value = JSON.stringify(texts);
      } catch (e) {
        console.warn("writeToCoreWidgets: widget write failed", e);
      }

      // also write to properties for compatibility
      node.properties = node.properties || {};
      node.properties.weights = Array.from(weights);
      node.properties.texts = Array.from(texts);

      if (node.graph) node.setDirtyCanvas(true, true);
    }

    // compute minimal node height for rowCount and ensure node.size[1] >= needed
    function ensureNodeMinHeight(node, rowCount) {
        const rowH = ROW_H;       // Höhe einer Tabellenzeile
        const base = BASE_H;       // Oberer Bereich (Titelzeile + Core Widgets)
        const extra = EXTRA_BOTTOM;       // Gewünschter zusätzlicher Abstand
        const needed = base + (rowCount + 4) * rowH + extra;

        // Mindesthöhe setzen
        node.min_height = needed;

        if (node.size[1] < needed) {
            node.size[1] = needed;
        }

        // Mindestbreite (für Tabelle + Delete Buttons)
        const minWidth = 380;
        node.min_width = minWidth;

        if (node.size[0] < minWidth) {
            node.size[0] = minWidth;
        }

        node.onResize = function(size) {
            size[1] = Math.max(size[1], node.min_height);
            size[0] = Math.max(size[0], node.min_width);
            return size;
        };

        node.flags = node.flags || {};
        node.flags.resizable = true;
        node.setSize(node.size);

        node.graph.setDirtyCanvas(true, true);
    }

    // ---------------- build DOM widget ----------------
    function buildDomWidget(node) {
      const container = document.createElement("div");
      container.style.boxSizing = "border-box";
      container.style.padding = "0px 6px 6px";
      container.style.width = "100%";
      container.style.color = "#ddd";
      container.style.fontFamily = "sans-serif";
      container.style.fontSize = "13px";
      container.style.userSelect = "none";

      // header
      const header = document.createElement("div");
      header.style.display = "flex";
      header.style.gap = "4px";
      header.style.alignItems = "center";
      header.style.marginBottom = "6px";
      const hThresh = document.createElement("div"); hThresh.textContent = "Weights"; hThresh.style.width = "50px";
      const hText = document.createElement("div"); hText.textContent = "Grades"; hText.style.flex = "1";
      header.appendChild(hThresh); header.appendChild(hText);
      container.appendChild(header);

      // rows container
      const rowsBox = document.createElement("div");
      rowsBox.style.display = "flex";
      rowsBox.style.flexDirection = "column";
      rowsBox.style.gap = ROW_GAP + "px";
      rowsBox.style.width = "100%";
      container.appendChild(rowsBox);

      // add button
      const addWrap = document.createElement("div");
      addWrap.style.display = "flex";
      addWrap.style.marginTop = "8px";
      addWrap.style.justifyContent = "flex-start";
      const addBtn = document.createElement("button");
      addBtn.textContent = "Add Row";
      addBtn.style.background = "#444";
      addBtn.style.color = "#fff";
      addBtn.style.border = "1px solid #222";
      addBtn.style.height = ADD_BTN_H + "px";
      addBtn.style.padding = "0 10px";
      addBtn.style.cursor = "pointer";
      addWrap.appendChild(addBtn);
      container.appendChild(addWrap);

      return { container, rowsBox, addBtn };
    }

    // render rows from core widgets into DOM; set up events
    function renderRows(node, domParts) {
      const { rowsBox, addBtn } = domParts;
      // read authoritative arrays
      let { weights, texts } = readFromCoreWidgets(node);

      // clear existing rows
      while (rowsBox.firstChild) rowsBox.removeChild(rowsBox.firstChild);

      // create rows
      for (let i = 0; i < weights.length; i++) {
        const row = document.createElement("div");
        row.style.display = "flex";
        row.style.alignItems = "center";
        row.style.gap = "6px";

        const thrInput = document.createElement("input");
        thrInput.type = "number"; thrInput.step = "0.1";  thrInput.min = "0.0";
        thrInput.value = String(weights[i]); thrInput.style.width = "50px";
        thrInput.style.boxSizing = "border-box"; thrInput.style.padding = "2px 2px";
        thrInput.style.background = "#111"; thrInput.style.border = "1px solid #333"; thrInput.style.color = "#fff";

        const txtInput = document.createElement("input");
        txtInput.type = "text"; txtInput.value = String(texts[i] ?? "");
        txtInput.style.flex = "1"; txtInput.style.boxSizing = "border-box";
        txtInput.style.padding = "2px 2px"; txtInput.style.background = "#111";
        txtInput.style.border = "1px solid #333"; txtInput.style.color = "#fff";

        const delBtn = document.createElement("button");
        delBtn.textContent = "Delete"; delBtn.style.background = "#533"; delBtn.style.color = "#fff";
        delBtn.style.border = "1px solid #700"; delBtn.style.padding = "2px 8px"; delBtn.style.cursor = "pointer";

        // events
        thrInput.addEventListener("change", (ev) => {
          const val = parseFloat(thrInput.value);
          const tcur = readFromCoreWidgets(node);
          tcur.weights[i] = Number.isFinite(val) ? val : 0.0;
          writeToCoreWidgets(node, tcur.weights, tcur.texts);
          renderRows(node, domParts);
          ensureNodeMinHeight(node, tcur.weights.length);
        });

        txtInput.addEventListener("change", (ev) => {
          const val = txtInput.value;
          const tcur = readFromCoreWidgets(node);
          tcur.texts[i] = String(val);
          writeToCoreWidgets(node, tcur.weights, tcur.texts);
          renderRows(node, domParts);
          ensureNodeMinHeight(node, tcur.weights.length);
        });

        delBtn.addEventListener("click", (ev) => {
          ev.stopPropagation();
          const tcur = readFromCoreWidgets(node);
          tcur.weights.splice(i, 1); tcur.texts.splice(i, 1);
          writeToCoreWidgets(node, tcur.weights, tcur.texts);
          renderRows(node, domParts);
          ensureNodeMinHeight(node, tcur.weights.length);
        });

        row.appendChild(thrInput);
        row.appendChild(txtInput);
        row.appendChild(delBtn);
        rowsBox.appendChild(row);
      }

      // addBtn handler (default value = 1.0)
      addBtn.onclick = (ev) => {
        ev.stopPropagation();
        const tcur = readFromCoreWidgets(node);
        const def = 1.0;
        tcur.weights.push(def); tcur.texts.push("");
        writeToCoreWidgets(node, tcur.weights, tcur.texts);
        renderRows(node, domParts);
        ensureNodeMinHeight(node, tcur.weights.length);
      };
    }

    // ---------------- attach to node ----------------
    function attach(node) {
      if (!node || node.__dom_widget_attached) return;
      if (!isTarget(node)) return;
      node.__dom_widget_attached = true;

      console.debug("[grade_variant_widget] attach node id:", node.id, "properties:", node.properties);

      // create DOM parts and attach
      const domParts = buildDomWidget(node);
      node.addDOMWidget("Weights Table", "custom", domParts.container);

      // initial render
      renderRows(node, domParts);

      // ensure min size
      const arrays = readFromCoreWidgets(node);
      ensureNodeMinHeight(node, arrays.weights.length);

      // Start polling core widget values to detect manual edits
      if (node.__widget_poll) clearInterval(node.__widget_poll);
      let lastT = JSON.stringify(arrays.weights);
      let lastX = JSON.stringify(arrays.texts);

      node.__widget_poll = setInterval(() => {
        const cur = readFromCoreWidgets(node);
        const curT = JSON.stringify(cur.weights);
        const curX = JSON.stringify(cur.texts);
        if (curT !== lastT || curX !== lastX) {
          lastT = curT; lastX = curX;
          try {
            renderRows(node, domParts);
            ensureNodeMinHeight(node, cur.weights.length);
            console.debug("[grade_variant_widget] detected external widget change -> re-render");
          } catch (e) { console.warn("re-render failed", e); }
        }
      }, POLL_MS);
    }

    // attach to existing nodes
    try {
      const g = appInstance.graph;
      if (g && Array.isArray(g._nodes)) {
        for (const n of g._nodes) {
          try { attach(n); } catch (e) { console.warn("attach existing failed", e); }
        }
      }
    } catch (e) { console.warn(e); }

    // hook new node creation
    try {
      const graph = appInstance.graph;
      if (graph) {
        const origAdd = graph.add;
        graph.add = function(node) {
          const res = origAdd.apply(this, arguments);
          try { attach(node); } catch (e) {}
          return res;
        };
      }
    } catch (e) { console.warn(e); }

    console.log("grade_variant_widget initialized");
  }
});
