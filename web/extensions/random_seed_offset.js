import { app } from "/scripts/app.js";

app.registerExtension({
    name: "comfyui_stereoscopic.autoseedoffset",
    async init(appInstance) {
        const graph = appInstance.graph;

        if (!graph) return;

        const origAdd = graph.add;

        graph.add = function(node) {
            const res = origAdd.apply(this, arguments);

            // Nur für den Node-Typ, bei dem du seed_offset setzen willst
            if (node.type === "RandomThreshold" || node.type === "BuildVariantIndex") {

                // setze zufälligen Wert
                let w = node.widgets?.find(w => w.name === "seed_offset");
                if (w) {
                    w.value = Math.floor(Math.random() * 2_147_000_000); // INT32
                    node.properties = node.properties || {};
                    node.properties.seed_offset = w.value;

                    node.setDirtyCanvas(true, true);
                    console.log("Assigned random seed_offset:", w.value, "to node", node.id);
                }
            }

            return res;
        };
    }
});

