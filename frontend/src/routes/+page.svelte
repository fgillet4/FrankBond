<script>
	import { onMount } from 'svelte';

	let atoms = [];
	let bonds = [];
	let arrows = [];
	let lonePairs = [];
	let texts = []; // { id, x, y, text, fontSize }

	// Graph representation of the molecule
	let moleculeGraph = {
		nodes: new Map(), // atom id -> atom data
		edges: new Map(), // bond id -> {atomId1, atomId2, type}
		adjacency: new Map() // atom id -> Set of connected atom ids
	};

	let selectedElement = 'C';
	let selectedTool = 'atom';
	let tempBond = null;
	let tempArrow = null;
	let svgElement;

	// Selection state
	let selectedAtoms = new Set();
	let selectedArrows = new Set();
	let selectedBonds = new Set();
	let selectedLonePairs = new Set();
	let selectedTexts = new Set();

	// Text editing overlay state
	let editingText = null;   // { id, x, y, fontSize } while a text is being edited
	let editInputValue = '';
	let textEditScreenPos = { x: 0, y: 0 };
	let textInputEl = null;   // bind:this for the overlay input

	// Context menu state
	let contextMenu = { visible: false, x: 0, y: 0 };

	// Educational modal state
	let showEducationalModal = false;

	// File input for loading molecules
	let fileInput;

	// Undo/Redo state management (double stack)
	let undoStack = [];
	let redoStack = [];
	const MAX_UNDO_HISTORY = 50;
	let isBoxSelecting = false;
	let boxStart = { x: 0, y: 0 };
	let boxEnd = { x: 0, y: 0 };

	// Export PNG state
	let isDrawingExportBox = false;
	let exportBoxStart = { x: 0, y: 0 };
	let exportBoxEnd = { x: 0, y: 0 };
	let exportBoxReady = false;

	// Pan and zoom state
	let zoom = 1;
	let pan = { x: 0, y: 0 };
	let isPanning = false;
	let lastPanPoint = { x: 0, y: 0 };
	let viewBox = { x: 0, y: 0, width: 800, height: 600 };

	// Drag state — group-aware
	let isDragging = false;
	let draggedAtomId = null; // anchor atom (for snap calc + cursor)
	let dragStartCanvasX = 0;
	let dragStartCanvasY = 0;
	let dragAtomSnapshots = new Map(); // id → {x, y}  of ALL selected atoms at drag start
	let dragArrowSnapshots = new Map(); // id → {startX,startY,endX,endY} of ALL selected arrows
	let dragTextSnapshots = new Map(); // id → {x, y} of ALL selected texts at drag start

	// Arrow handle drag state (resize arrow endpoints)
	let arrowHandleDrag = null; // { arrowId, handle: 'start'|'end' }

	// Shift+drag to move selection from anywhere on the canvas
	let shiftMoveStart = null; // { clientX, clientY, canvasX, canvasY } — set on shift+mousedown
	let justFinishedShiftDrag = false; // suppresses the subsequent click event

	// Grid system
	let gridEnabled = true;
	let gridType = 'hexagonal'; // default hex for bondline
	let gridSize = 40;
	let snapToGrid = true;

	// Debug cursor
	let debugCursor = { x: 0, y: 0, visible: false };

	// --- BONDLINE MODE ---
	let bondlineMode = false;

	// --- CLIPBOARD (internal — copy/paste structures) ---
	let clipboard = null; // { atoms, bonds, arrows, lonePairs }

	// --- AUTH & STRUCTURES ---
	let fsToken = null;
	let currentUser = null;
	let savedStructures = [];
	let structureName = 'Untitled';
	let showStructuresPanel = false;
	let structureSaveError = '';
	let structuresLoading = false;

	const API_BASE = '/api';

	const elements = ['C', 'O', 'N', 'S', 'P', 'H', 'F', 'Cl', 'Br', 'I'];
	const bondTypes = ['single', 'double', 'triple'];

	// Reactive statement to regenerate grid when type or size changes
	$: gridPoints = generateGridPoints(gridType, gridSize, viewBox);

	$: if (svgElement) {
		if (!isPanning) svgElement.style.cursor = selectedTool === 'export' ? 'crosshair' : 'default';
	}

	function generateId() {
		return Math.random().toString(36).substr(2, 9);
	}

	function updateViewBox() {
		viewBox = {
			x: -pan.x,
			y: -pan.y,
			width: 800 / zoom,
			height: 600 / zoom
		};
	}

	function getCanvasCoordinates(event) {
		// Get the SVG's actual rendered viewport
		const rect = svgElement.getBoundingClientRect();

		// Calculate the actual viewBox aspect ratio vs rendered aspect ratio
		const viewBoxAspect = viewBox.width / viewBox.height;
		const renderedAspect = rect.width / rect.height;

		let actualSVGWidth, actualSVGHeight, offsetX, offsetY;

		if (viewBoxAspect > renderedAspect) {
			// ViewBox is wider — letterboxed vertically
			actualSVGWidth = rect.width;
			actualSVGHeight = rect.width / viewBoxAspect;
			offsetX = 0;
			offsetY = (rect.height - actualSVGHeight) / 2;
		} else {
			// ViewBox is taller than container — letterboxed horizontally
			actualSVGWidth = rect.height * viewBoxAspect;
			actualSVGHeight = rect.height;
			offsetX = (rect.width - actualSVGWidth) / 2;
			offsetY = 0;
		}

		// Adjust mouse coordinates for letterboxing
		const adjustedX = event.offsetX - offsetX;
		const adjustedY = event.offsetY - offsetY;

		// Convert to world coordinates
		let x = (adjustedX / actualSVGWidth) * viewBox.width + viewBox.x;
		let y = (adjustedY / actualSVGHeight) * viewBox.height + viewBox.y;

		// Snap to grid if enabled
		if (snapToGrid && gridEnabled) {
			const snapped = snapToGridPoint(x, y);
			x = snapped.x;
			y = snapped.y;
		}

		return { x, y };
	}

	function snapToGridPoint(x, y) {
		if (gridType === 'square') {
			return {
				x: Math.round(x / gridSize) * gridSize,
				y: Math.round(y / gridSize) * gridSize
			};
		} else if (gridType === 'hexagonal') {
			// Hexagonal grid — 0°/60°/120° angles, good for flat aromatic rings
			const hexHeight = gridSize * Math.sqrt(3) / 2;
			const hexWidth = gridSize;

			const row = Math.round(y / hexHeight);
			const col = Math.round((x - (row % 2) * (hexWidth / 2)) / hexWidth);

			const gridX = col * hexWidth + (row % 2) * (hexWidth / 2);
			const gridY = row * hexHeight;

			return { x: gridX, y: gridY };
		} else if (gridType === 'chair') {
			// Chair/isometric grid — hexagonal lattice rotated 30°.
			// Natural bond angles: 30°/90°/150°. Perfect for:
			//   • C-C bonds in chair rings (30° and 150°)
			//   • Axial bonds (90°, perfectly vertical)
			//   • Newman projections and perspective drawings
			const cos30 = Math.sqrt(3) / 2;
			const sin30 = 0.5;

			// Rotate the incoming point by -30° into hex-lattice space
			const hx = x * cos30 + y * sin30;
			const hy = -x * sin30 + y * cos30;

			// Snap in hex-lattice space
			const hexHeight = gridSize * Math.sqrt(3) / 2;
			const row = Math.round(hy / hexHeight);
			const col = Math.round((hx - (row % 2) * (gridSize / 2)) / gridSize);
			const snapHx = col * gridSize + (row % 2) * (gridSize / 2);
			const snapHy = row * hexHeight;

			// Rotate the snapped point back by +30°
			return {
				x: snapHx * cos30 - snapHy * sin30,
				y: snapHx * sin30 + snapHy * cos30
			};
		}
		return { x, y };
	}

	function generateGridPoints() {
		const points = [];
		const margin = 100;
		const startX = viewBox.x - margin;
		const endX = viewBox.x + viewBox.width + margin;
		const startY = viewBox.y - margin;
		const endY = viewBox.y + viewBox.height + margin;

		if (gridType === 'square') {
			const firstX = Math.floor(startX / gridSize) * gridSize;
			const firstY = Math.floor(startY / gridSize) * gridSize;

			for (let x = firstX; x <= endX; x += gridSize) {
				for (let y = firstY; y <= endY; y += gridSize) {
					points.push({ x, y });
				}
			}
		} else if (gridType === 'hexagonal') {
			const hexHeight = gridSize * Math.sqrt(3) / 2;
			const hexWidth = gridSize;

			const firstRow = Math.floor(startY / hexHeight);
			const lastRow = Math.ceil(endY / hexHeight);
			const firstCol = Math.floor(startX / hexWidth);
			const lastCol = Math.ceil(endX / hexWidth);

			for (let row = firstRow; row <= lastRow; row++) {
				for (let col = firstCol; col <= lastCol; col++) {
					const offsetX = (row % 2) * (hexWidth / 2);
					const x = col * hexWidth + offsetX;
					const y = row * hexHeight;

					if (x >= startX && x <= endX && y >= startY && y <= endY) {
						points.push({ x, y });
					}
				}
			}
		} else if (gridType === 'chair') {
			// Generate the rotated-30° hex lattice for chair conformations.
			// Work in hex-lattice space, then rotate each point by +30°.
			const cos30 = Math.sqrt(3) / 2;
			const sin30 = 0.5;
			const hexHeight = gridSize * Math.sqrt(3) / 2;

			// Conservative bounds in hex-lattice space (rotate viewport corners by -30°)
			const corners = [
				{ x: startX, y: startY }, { x: endX, y: startY },
				{ x: startX, y: endY },   { x: endX, y: endY }
			].map(c => ({
				hx: c.x * cos30 + c.y * sin30,
				hy: -c.x * sin30 + c.y * cos30
			}));
			const hxMin = Math.min(...corners.map(c => c.hx)) - gridSize;
			const hxMax = Math.max(...corners.map(c => c.hx)) + gridSize;
			const hyMin = Math.min(...corners.map(c => c.hy)) - gridSize;
			const hyMax = Math.max(...corners.map(c => c.hy)) + gridSize;

			const firstRow = Math.floor(hyMin / hexHeight);
			const lastRow  = Math.ceil(hyMax / hexHeight);
			const firstCol = Math.floor(hxMin / gridSize);
			const lastCol  = Math.ceil(hxMax / gridSize);

			for (let row = firstRow; row <= lastRow; row++) {
				for (let col = firstCol; col <= lastCol; col++) {
					const hx = col * gridSize + (row % 2) * (gridSize / 2);
					const hy = row * hexHeight;
					// Rotate by +30° back to screen space
					const sx = hx * cos30 - hy * sin30;
					const sy = hx * sin30 + hy * cos30;
					if (sx >= startX && sx <= endX && sy >= startY && sy <= endY) {
						points.push({ x: sx, y: sy });
					}
				}
			}
		}

		return points;
	}

	// Convert canvas (SVG world) coordinates back to screen (client) coordinates.
	// Inverse of getCanvasCoordinates — needed to position the text editing overlay.
	function getScreenPosition(canvasX, canvasY) {
		if (!svgElement) return { x: 0, y: 0 };
		const rect = svgElement.getBoundingClientRect();
		const viewBoxAspect = viewBox.width / viewBox.height;
		const renderedAspect = rect.width / rect.height;

		let actualSVGWidth, actualSVGHeight, offsetX, offsetY;
		if (viewBoxAspect > renderedAspect) {
			actualSVGWidth = rect.width;
			actualSVGHeight = rect.width / viewBoxAspect;
			offsetX = 0;
			offsetY = (rect.height - actualSVGHeight) / 2;
		} else {
			actualSVGWidth = rect.height * viewBoxAspect;
			actualSVGHeight = rect.height;
			offsetX = (rect.width - actualSVGWidth) / 2;
			offsetY = 0;
		}

		return {
			x: ((canvasX - viewBox.x) / viewBox.width) * actualSVGWidth + offsetX + rect.left,
			y: ((canvasY - viewBox.y) / viewBox.height) * actualSVGHeight + offsetY + rect.top
		};
	}

	function openTextEdit(id, x, y, fontSize, initialValue) {
		editingText = { id, x, y, fontSize };
		editInputValue = initialValue;
		textEditScreenPos = getScreenPosition(x, y);
		// Focus the input after Svelte renders it
		setTimeout(() => textInputEl && textInputEl.focus(), 0);
	}

	function addText(x, y) {
		saveState();
		const id = generateId();
		const newText = { id, x, y, text: '', fontSize: 16 };
		texts = [...texts, newText];
		openTextEdit(id, x, y, 16, '');
	}

	function commitTextEdit() {
		if (!editingText) return;
		const trimmed = editInputValue.trim();
		if (trimmed === '') {
			// Empty text — remove it
			texts = texts.filter(t => t.id !== editingText.id);
		} else {
			texts = texts.map(t => t.id === editingText.id ? { ...t, text: trimmed } : t);
		}
		editingText = null;
	}

	function cancelTextEdit() {
		if (!editingText) return;
		// If it was a brand-new (empty) text, remove it
		const existing = texts.find(t => t.id === editingText.id);
		if (existing && existing.text === '') texts = texts.filter(t => t.id !== editingText.id);
		editingText = null;
	}

	function startEditText(textId) {
		const t = texts.find(t2 => t2.id === textId);
		if (t) openTextEdit(t.id, t.x, t.y, t.fontSize, t.text);
	}

	function setSelectedArrowWidth(width) {
		arrows = arrows.map(ar =>
			selectedArrows.has(ar.id) ? { ...ar, strokeWidth: width } : ar
		);
	}

	function handleSVGMouseMove(event) {
		if (!isPanning) {
			const coords = getCanvasCoordinates(event);
			debugCursor = { x: coords.x, y: coords.y, visible: true };

			if (tempArrow && selectedTool === 'arrow') {
				updateArrow(coords.x, coords.y);
			}
		}
	}

	function handleSVGMouseLeave() {
		debugCursor.visible = false;
		// Release any handle drag if mouse leaves the SVG
		if (arrowHandleDrag) arrowHandleDrag = null;
	}

	let justFinishedBoxSelect = false;

	function handleSVGClick(event) {
		if (isPanning || justFinishedBoxSelect || justFinishedShiftDrag) {
			justFinishedBoxSelect = false;
			justFinishedShiftDrag = false;
			return;
		}

		const coords = getCanvasCoordinates(event);

		if (selectedTool === 'atom') {
			addAtom(coords.x, coords.y);
		} else if (selectedTool === 'text') {
			addText(coords.x, coords.y);
		} else if (selectedTool === 'bond') {
			// Click on empty space: auto-place a vertex and chain bonds
			placeAtomAndContinueBond(coords.x, coords.y);
		} else if (selectedTool === 'arrow') {
			if (tempArrow) {
				completeArrow();
			} else {
				startArrow(coords.x, coords.y);
			}
		} else if (selectedTool === 'select') {
			if (!event.shiftKey) {
				selectedAtoms.clear();
				selectedArrows.clear();
				selectedBonds.clear();
				selectedLonePairs.clear();
				selectedAtoms = new Set(selectedAtoms);
				selectedArrows = new Set(selectedArrows);
				selectedBonds = new Set(selectedBonds);
				selectedLonePairs = new Set(selectedLonePairs);
				atoms = atoms.map(atom => ({ ...atom, selected: false }));
			}
		}
	}

	// Place a new atom at (x,y) and either start or continue a bond chain.
	// If a bond was in progress, complete it to the new atom and immediately
	// start the next bond from that atom (for fast chain drawing).
	function placeAtomAndContinueBond(x, y) {
		saveState();

		const newAtom = {
			id: generateId(),
			x,
			y,
			element: selectedElement,
			selected: false
		};
		atoms = [...atoms, newAtom];
		moleculeGraph.nodes.set(newAtom.id, newAtom);
		moleculeGraph.adjacency.set(newAtom.id, new Set());

		if (tempBond && tempBond.startAtomId !== newAtom.id) {
			// Complete the in-progress bond to the new atom
			const newBond = {
				id: generateId(),
				atomId1: tempBond.startAtomId,
				atomId2: newAtom.id,
				type: 'single'
			};
			bonds = [...bonds, newBond];
			moleculeGraph.edges.set(newBond.id, newBond);
			moleculeGraph.adjacency.get(newBond.atomId1).add(newBond.atomId2);
			moleculeGraph.adjacency.get(newBond.atomId2).add(newBond.atomId1);
		}

		// Always start the next bond from the newly placed atom
		tempBond = { startAtomId: newAtom.id, x: newAtom.x, y: newAtom.y };
	}

	function addAtom(x, y) {
		saveState();

		const newAtom = {
			id: generateId(),
			x,
			y,
			element: selectedElement,
			selected: false
		};
		atoms = [...atoms, newAtom];

		moleculeGraph.nodes.set(newAtom.id, newAtom);
		moleculeGraph.adjacency.set(newAtom.id, new Set());
	}

	function selectAtom(atomId, addToSelection = false) {
		if (justFinishedShiftDrag) { justFinishedShiftDrag = false; return; }
		if (addToSelection) {
			if (selectedAtoms.has(atomId)) {
				selectedAtoms.delete(atomId);
			} else {
				selectedAtoms.add(atomId);
			}
		} else {
			selectedAtoms.clear();
			selectedAtoms.add(atomId);
		}
		selectedAtoms = new Set(selectedAtoms);

		atoms = atoms.map(atom => ({
			...atom,
			selected: selectedAtoms.has(atom.id)
		}));
	}

	function startBond(atomId, event) {
		if (selectedTool === 'bond') {
			event.stopPropagation();
			const atom = atoms.find(a => a.id === atomId);
			if (atom) {
				tempBond = { startAtomId: atomId, x: atom.x, y: atom.y };
			}
		}
	}

	function completeBond(endAtomId, event) {
		if (tempBond && tempBond.startAtomId !== endAtomId) {
			event.stopPropagation();
			saveState();

			const newBond = {
				id: generateId(),
				atomId1: tempBond.startAtomId,
				atomId2: endAtomId,
				type: 'single'
			};
			bonds = [...bonds, newBond];

			moleculeGraph.edges.set(newBond.id, newBond);
			if (!moleculeGraph.adjacency.has(newBond.atomId1)) {
				moleculeGraph.adjacency.set(newBond.atomId1, new Set());
			}
			if (!moleculeGraph.adjacency.has(newBond.atomId2)) {
				moleculeGraph.adjacency.set(newBond.atomId2, new Set());
			}
			moleculeGraph.adjacency.get(newBond.atomId1).add(newBond.atomId2);
			moleculeGraph.adjacency.get(newBond.atomId2).add(newBond.atomId1);

			// Continue chain from the atom we just connected to
			const endAtom = atoms.find(a => a.id === endAtomId);
			if (endAtom) {
				tempBond = { startAtomId: endAtomId, x: endAtom.x, y: endAtom.y };
			} else {
				tempBond = null;
			}
		} else if (tempBond && tempBond.startAtomId === endAtomId) {
			// Clicked the same atom — cancel bond drawing
			event.stopPropagation();
			tempBond = null;
		}
	}

	function startArrow(x, y) {
		if (!tempArrow) {
			tempArrow = { startX: x, startY: y, endX: x, endY: y };
		}
	}

	function updateArrow(x, y) {
		if (tempArrow) {
			tempArrow.endX = x;
			tempArrow.endY = y;
		}
	}

	function completeArrow() {
		if (tempArrow) {
			saveState();

			const newArrow = {
				id: generateId(),
				startX: tempArrow.startX,
				startY: tempArrow.startY,
				endX: tempArrow.endX,
				endY: tempArrow.endY,
				type: 'reaction'
			};
			arrows = [...arrows, newArrow];
			tempArrow = null;
		}
	}

	function addLonePair(atomId, angle) {
		saveState();

		const newLonePair = {
			id: generateId(),
			atomId: atomId,
			angle: angle
		};
		lonePairs = [...lonePairs, newLonePair];
	}

	function getLonePairPosition(atomId, angle) {
		const atom = atoms.find(a => a.id === atomId);
		if (!atom) return { x: 0, y: 0 };

		const distance = 25;
		return {
			x: atom.x + Math.cos(angle) * distance,
			y: atom.y + Math.sin(angle) * distance
		};
	}

	function saveState() {
		const state = {
			atoms: JSON.parse(JSON.stringify(atoms)),
			bonds: JSON.parse(JSON.stringify(bonds)),
			arrows: JSON.parse(JSON.stringify(arrows)),
			lonePairs: JSON.parse(JSON.stringify(lonePairs)),
			texts: JSON.parse(JSON.stringify(texts)),
			selectedAtoms: new Set(selectedAtoms),
			selectedArrows: new Set(selectedArrows),
			selectedBonds: new Set(selectedBonds),
			selectedLonePairs: new Set(selectedLonePairs),
			selectedTexts: new Set(selectedTexts)
		};

		undoStack.push(state);
		if (undoStack.length > MAX_UNDO_HISTORY) {
			undoStack.shift();
		}

		redoStack = [];
	}

	function restoreState(state) {
		atoms = JSON.parse(JSON.stringify(state.atoms));
		bonds = JSON.parse(JSON.stringify(state.bonds));
		arrows = JSON.parse(JSON.stringify(state.arrows));
		lonePairs = JSON.parse(JSON.stringify(state.lonePairs));
		texts = state.texts ? JSON.parse(JSON.stringify(state.texts)) : [];
		selectedAtoms = new Set(state.selectedAtoms);
		selectedArrows = new Set(state.selectedArrows);
		selectedBonds = new Set(state.selectedBonds);
		selectedLonePairs = new Set(state.selectedLonePairs);
		selectedTexts = state.selectedTexts ? new Set(state.selectedTexts) : new Set();

		moleculeGraph.nodes.clear();
		moleculeGraph.edges.clear();
		moleculeGraph.adjacency.clear();

		atoms.forEach(atom => {
			moleculeGraph.nodes.set(atom.id, atom);
			moleculeGraph.adjacency.set(atom.id, new Set());
		});

		bonds.forEach(bond => {
			moleculeGraph.edges.set(bond.id, bond);
			if (moleculeGraph.adjacency.has(bond.atomId1) && moleculeGraph.adjacency.has(bond.atomId2)) {
				moleculeGraph.adjacency.get(bond.atomId1).add(bond.atomId2);
				moleculeGraph.adjacency.get(bond.atomId2).add(bond.atomId1);
			}
		});
	}

	function undo() {
		if (undoStack.length > 0) {
			const currentState = {
				atoms: JSON.parse(JSON.stringify(atoms)),
				bonds: JSON.parse(JSON.stringify(bonds)),
				arrows: JSON.parse(JSON.stringify(arrows)),
				lonePairs: JSON.parse(JSON.stringify(lonePairs)),
				texts: JSON.parse(JSON.stringify(texts)),
				selectedAtoms: new Set(selectedAtoms),
				selectedArrows: new Set(selectedArrows),
				selectedBonds: new Set(selectedBonds),
				selectedLonePairs: new Set(selectedLonePairs),
				selectedTexts: new Set(selectedTexts)
			};
			redoStack.push(currentState);

			const previousState = undoStack.pop();
			restoreState(previousState);
		}
	}

	function redo() {
		if (redoStack.length > 0) {
			saveState();
			undoStack.pop();

			const nextState = redoStack.pop();
			restoreState(nextState);
		}
	}

	function beginGroupDrag(anchorAtomId, event) {
		event.stopPropagation();
		saveState();

		isDragging = true;
		draggedAtomId = anchorAtomId;

		const coords = getCanvasCoordinates(event);
		dragStartCanvasX = coords.x;
		dragStartCanvasY = coords.y;

		// Snapshot every selected atom
		dragAtomSnapshots.clear();
		selectedAtoms.forEach(id => {
			const atom = atoms.find(a => a.id === id);
			if (atom) dragAtomSnapshots.set(id, { x: atom.x, y: atom.y });
		});

		// Snapshot every selected arrow
		dragArrowSnapshots.clear();
		selectedArrows.forEach(id => {
			const arrow = arrows.find(ar => ar.id === id);
			if (arrow) dragArrowSnapshots.set(id, {
				startX: arrow.startX, startY: arrow.startY,
				endX: arrow.endX,   endY: arrow.endY
			});
		});

		// Snapshot every selected text
		dragTextSnapshots.clear();
		selectedTexts.forEach(id => {
			const t = texts.find(t2 => t2.id === id);
			if (t) dragTextSnapshots.set(id, { x: t.x, y: t.y });
		});
	}

	function startAtomDrag(atomId, event) {
		if (selectedTool === 'select' && selectedAtoms.has(atomId)) {
			beginGroupDrag(atomId, event);
		}
	}

	// Called when mousedown on a selected arrow body (not a handle)
	function startArrowBodyDrag(arrowId, event) {
		if (selectedTool !== 'select' || !selectedArrows.has(arrowId)) return;
		// Use a dummy anchor atom id so the drag system is happy;
		// if no atoms are selected we still need to drag arrows
		event.stopPropagation();
		saveState();

		isDragging = true;
		draggedAtomId = null; // no atom anchor, snap from cursor delta

		const coords = getCanvasCoordinates(event);
		dragStartCanvasX = coords.x;
		dragStartCanvasY = coords.y;

		dragAtomSnapshots.clear();
		selectedAtoms.forEach(id => {
			const atom = atoms.find(a => a.id === id);
			if (atom) dragAtomSnapshots.set(id, { x: atom.x, y: atom.y });
		});

		dragArrowSnapshots.clear();
		selectedArrows.forEach(id => {
			const arrow = arrows.find(ar => ar.id === id);
			if (arrow) dragArrowSnapshots.set(id, {
				startX: arrow.startX, startY: arrow.startY,
				endX: arrow.endX,   endY: arrow.endY
			});
		});

		dragTextSnapshots.clear();
		selectedTexts.forEach(id => {
			const t = texts.find(t2 => t2.id === id);
			if (t) dragTextSnapshots.set(id, { x: t.x, y: t.y });
		});
	}

	// Called when mousedown on an arrow endpoint handle
	function startArrowHandleDrag(arrowId, handle, event) {
		event.stopPropagation();
		if (!arrowHandleDrag) saveState();
		arrowHandleDrag = { arrowId, handle };
	}

	function applyGroupDragDelta(dx, dy) {
		// Move all snapshotted atoms
		atoms = atoms.map(atom => {
			const snap = dragAtomSnapshots.get(atom.id);
			if (!snap) return atom;
			const newAtom = { ...atom, x: snap.x + dx, y: snap.y + dy };
			moleculeGraph.nodes.set(atom.id, newAtom);
			return newAtom;
		});
		bonds = [...bonds];

		// Move all snapshotted arrows
		arrows = arrows.map(arrow => {
			const snap = dragArrowSnapshots.get(arrow.id);
			if (!snap) return arrow;
			return {
				...arrow,
				startX: snap.startX + dx, startY: snap.startY + dy,
				endX: snap.endX + dx,   endY: snap.endY + dy
			};
		});

		// Move all snapshotted texts
		texts = texts.map(t => {
			const snap = dragTextSnapshots.get(t.id);
			if (!snap) return t;
			return { ...t, x: snap.x + dx, y: snap.y + dy };
		});
	}

	function isBondInBox(bond, minX, maxX, minY, maxY) {
		const atom1 = atoms.find(a => a.id === bond.atomId1);
		const atom2 = atoms.find(a => a.id === bond.atomId2);

		if (!atom1 || !atom2) return false;

		const startInBox = atom1.x >= minX && atom1.x <= maxX && atom1.y >= minY && atom1.y <= maxY;
		const endInBox = atom2.x >= minX && atom2.x <= maxX && atom2.y >= minY && atom2.y <= maxY;

		return startInBox || endInBox;
	}

	function isLonePairInBox(lonePair, minX, maxX, minY, maxY) {
		const position = getLonePairPosition(lonePair.atomId, lonePair.angle);
		return position.x >= minX && position.x <= maxX && position.y >= minY && position.y <= maxY;
	}

	function isArrowInBox(arrow, minX, maxX, minY, maxY) {
		const startInBox = arrow.startX >= minX && arrow.startX <= maxX && arrow.startY >= minY && arrow.startY <= maxY;
		const endInBox = arrow.endX >= minX && arrow.endX <= maxX && arrow.endY >= minY && arrow.endY <= maxY;
		return startInBox || endInBox;
	}

	function getAtomColor(element) {
		const colors = {
			'C': '#000000',
			'O': '#ff0000',
			'N': '#0000ff',
			'S': '#ccaa00',
			'P': '#ff8000',
			'H': '#666666',
			'F': '#00cc44',
			'Cl': '#1fa01f',
			'Br': '#a62929',
			'I': '#940094',
			'OH': '#ff0000',
			'MeO': '#ff0000'
		};
		return colors[element] || '#000000';
	}

	// In bondline mode, atom circle bg color for heteroatoms is white (text label only)
	function getBondlineLabelColor(element) {
		return getAtomColor(element);
	}

	function getBondPaths(bond) {
		const atom1 = atoms.find(a => a.id === bond.atomId1);
		const atom2 = atoms.find(a => a.id === bond.atomId2);

		if (!atom1 || !atom2) return [];

		const dx = atom2.x - atom1.x;
		const dy = atom2.y - atom1.y;
		const length = Math.sqrt(dx * dx + dy * dy);
		if (length === 0) return [];
		const unitX = dx / length;
		const unitY = dy / length;

		// In bondline mode, shorten bonds to heteroatoms so the line doesn't overlap text
		const ATOM_RADIUS = 15;
		const BONDLINE_HETERO_OFFSET = 10; // shorter so text is legible

		let x1 = atom1.x, y1 = atom1.y;
		let x2 = atom2.x, y2 = atom2.y;

		if (bondlineMode) {
			// Shorten ends that touch non-carbon atoms
			if (atom1.element !== 'C') {
				x1 = atom1.x + unitX * BONDLINE_HETERO_OFFSET;
				y1 = atom1.y + unitY * BONDLINE_HETERO_OFFSET;
			}
			if (atom2.element !== 'C') {
				x2 = atom2.x - unitX * BONDLINE_HETERO_OFFSET;
				y2 = atom2.y - unitY * BONDLINE_HETERO_OFFSET;
			}
		} else {
			// Lewis mode: shorten to atom circle edge
			x1 = atom1.x + unitX * ATOM_RADIUS;
			y1 = atom1.y + unitY * ATOM_RADIUS;
			x2 = atom2.x - unitX * ATOM_RADIUS;
			y2 = atom2.y - unitY * ATOM_RADIUS;
		}

		// Perpendicular vector for parallel bonds
		const perpX = -unitY * 3;
		const perpY = unitX * 3;

		if (bond.type === 'single') {
			return [`M ${x1} ${y1} L ${x2} ${y2}`];
		} else if (bond.type === 'double') {
			// Main line on bond axis, second line floating to one side
			const dPerpX = -unitY * 4;
			const dPerpY = unitX * 4;
			return [
				`M ${x1} ${y1} L ${x2} ${y2}`,
				`M ${x1 + dPerpX} ${y1 + dPerpY} L ${x2 + dPerpX} ${y2 + dPerpY}`
			];
		} else if (bond.type === 'triple') {
			return [
				`M ${x1} ${y1} L ${x2} ${y2}`,
				`M ${x1 + perpX} ${y1 + perpY} L ${x2 + perpX} ${y2 + perpY}`,
				`M ${x1 - perpX} ${y1 - perpY} L ${x2 - perpX} ${y2 - perpY}`
			];
		}

		return [];
	}

	function deleteSelected() {
		if (selectedAtoms.size > 0 || selectedArrows.size > 0 || selectedBonds.size > 0 || selectedLonePairs.size > 0 || selectedTexts.size > 0) {
			saveState();

			const atomIdsToDelete = Array.from(selectedAtoms);

			atoms = atoms.filter(atom => !selectedAtoms.has(atom.id));

			const bondsToDelete = bonds.filter(bond =>
				selectedAtoms.has(bond.atomId1) || selectedAtoms.has(bond.atomId2)
			);
			bonds = bonds.filter(bond =>
				!selectedAtoms.has(bond.atomId1) && !selectedAtoms.has(bond.atomId2)
			);

			lonePairs = lonePairs.filter(lp => !selectedAtoms.has(lp.atomId));
			arrows = arrows.filter(arrow => !selectedArrows.has(arrow.id));
			lonePairs = lonePairs.filter(lp => !selectedLonePairs.has(lp.id));

			const selectedBondsToDelete = bonds.filter(bond => selectedBonds.has(bond.id));
			bonds = bonds.filter(bond => !selectedBonds.has(bond.id));

			selectedBondsToDelete.forEach(bond => {
				moleculeGraph.edges.delete(bond.id);
				if (moleculeGraph.adjacency.has(bond.atomId1)) {
					moleculeGraph.adjacency.get(bond.atomId1).delete(bond.atomId2);
				}
				if (moleculeGraph.adjacency.has(bond.atomId2)) {
					moleculeGraph.adjacency.get(bond.atomId2).delete(bond.atomId1);
				}
			});

			atomIdsToDelete.forEach(atomId => {
				moleculeGraph.nodes.delete(atomId);
				moleculeGraph.adjacency.delete(atomId);
			});

			bondsToDelete.forEach(bond => {
				moleculeGraph.edges.delete(bond.id);
				if (moleculeGraph.adjacency.has(bond.atomId1)) {
					moleculeGraph.adjacency.get(bond.atomId1).delete(bond.atomId2);
				}
				if (moleculeGraph.adjacency.has(bond.atomId2)) {
					moleculeGraph.adjacency.get(bond.atomId2).delete(bond.atomId1);
				}
			});

			texts = texts.filter(t => !selectedTexts.has(t.id));

			selectedAtoms.clear();
			selectedArrows.clear();
			selectedBonds.clear();
			selectedLonePairs.clear();
			selectedTexts.clear();
			selectedAtoms = new Set(selectedAtoms);
			selectedArrows = new Set(selectedArrows);
			selectedBonds = new Set(selectedBonds);
			selectedLonePairs = new Set(selectedLonePairs);
			selectedTexts = new Set(selectedTexts);
		}
	}

	function selectAll() {
		selectedAtoms.clear();
		selectedArrows.clear();
		selectedBonds.clear();
		selectedLonePairs.clear();
		selectedTexts.clear();

		atoms.forEach(atom => selectedAtoms.add(atom.id));
		arrows.forEach(arrow => selectedArrows.add(arrow.id));
		bonds.forEach(bond => selectedBonds.add(bond.id));
		lonePairs.forEach(lp => selectedLonePairs.add(lp.id));
		texts.forEach(t => selectedTexts.add(t.id));

		selectedAtoms = new Set(selectedAtoms);
		selectedArrows = new Set(selectedArrows);
		selectedBonds = new Set(selectedBonds);
		selectedLonePairs = new Set(selectedLonePairs);
		selectedTexts = new Set(selectedTexts);

		atoms = atoms.map(atom => ({ ...atom, selected: true }));
	}

	// Copy selected atoms (+ bonds entirely within the selection, lone pairs, arrows).
	// If nothing is selected, copy everything.
	function copySelected() {
		const sourceAtoms = selectedAtoms.size > 0
			? atoms.filter(a => selectedAtoms.has(a.id))
			: atoms;
		const sourceAtomIds = new Set(sourceAtoms.map(a => a.id));

		// Only include bonds where BOTH endpoints are in the copied set
		const sourceBonds = bonds.filter(b =>
			sourceAtomIds.has(b.atomId1) && sourceAtomIds.has(b.atomId2)
		);
		const sourceLonePairs = lonePairs.filter(lp => sourceAtomIds.has(lp.atomId));
		const sourceArrows = selectedArrows.size > 0
			? arrows.filter(a => selectedArrows.has(a.id))
			: (selectedAtoms.size === 0 ? arrows : []);

		if (sourceAtoms.length === 0 && sourceArrows.length === 0) return;

		clipboard = {
			atoms: JSON.parse(JSON.stringify(sourceAtoms)),
			bonds: JSON.parse(JSON.stringify(sourceBonds)),
			lonePairs: JSON.parse(JSON.stringify(sourceLonePairs)),
			arrows: JSON.parse(JSON.stringify(sourceArrows))
		};
	}

	// Paste the clipboard contents offset by one grid step, select the pasted items.
	function pasteClipboard() {
		if (!clipboard) return;
		saveState();

		const offset = snapToGrid ? gridSize : 30;
		const dx = offset;
		const dy = offset;

		// Build an id-remap so we don't duplicate ids
		const idMap = new Map(); // old id -> new id
		clipboard.atoms.forEach(a => idMap.set(a.id, generateId()));
		clipboard.bonds.forEach(b => idMap.set(b.id, generateId()));
		clipboard.lonePairs.forEach(lp => idMap.set(lp.id, generateId()));
		clipboard.arrows.forEach(ar => idMap.set(ar.id, generateId()));

		const newAtoms = clipboard.atoms.map(a => ({
			...a,
			id: idMap.get(a.id),
			x: a.x + dx,
			y: a.y + dy,
			selected: true
		}));
		const newBonds = clipboard.bonds.map(b => ({
			...b,
			id: idMap.get(b.id),
			atomId1: idMap.get(b.atomId1),
			atomId2: idMap.get(b.atomId2)
		}));
		const newLonePairs = clipboard.lonePairs.map(lp => ({
			...lp,
			id: idMap.get(lp.id),
			atomId: idMap.get(lp.atomId)
		}));
		const newArrows = clipboard.arrows.map(ar => ({
			...ar,
			id: idMap.get(ar.id),
			startX: ar.startX + dx,
			startY: ar.startY + dy,
			endX: ar.endX + dx,
			endY: ar.endY + dy
		}));

		// Add to canvas
		atoms = [...atoms, ...newAtoms];
		bonds = [...bonds, ...newBonds];
		lonePairs = [...lonePairs, ...newLonePairs];
		arrows = [...arrows, ...newArrows];

		// Update graph
		newAtoms.forEach(a => {
			moleculeGraph.nodes.set(a.id, a);
			moleculeGraph.adjacency.set(a.id, new Set());
		});
		newBonds.forEach(b => {
			moleculeGraph.edges.set(b.id, b);
			if (!moleculeGraph.adjacency.has(b.atomId1)) moleculeGraph.adjacency.set(b.atomId1, new Set());
			if (!moleculeGraph.adjacency.has(b.atomId2)) moleculeGraph.adjacency.set(b.atomId2, new Set());
			moleculeGraph.adjacency.get(b.atomId1).add(b.atomId2);
			moleculeGraph.adjacency.get(b.atomId2).add(b.atomId1);
		});

		// Select only the pasted items
		selectedAtoms = new Set(newAtoms.map(a => a.id));
		selectedBonds = new Set(newBonds.map(b => b.id));
		selectedArrows = new Set(newArrows.map(ar => ar.id));
		selectedLonePairs = new Set(newLonePairs.map(lp => lp.id));

		// Shift clipboard offset so repeated pastes don't stack exactly
		clipboard = {
			...clipboard,
			atoms: clipboard.atoms.map(a => ({ ...a, x: a.x + dx, y: a.y + dy })),
			arrows: clipboard.arrows.map(ar => ({
				...ar,
				startX: ar.startX + dx, startY: ar.startY + dy,
				endX: ar.endX + dx,   endY: ar.endY + dy
			}))
		};
	}

	function handleKeyDown(event) {
		if (event.key === 'Escape') {
			// Cancel any in-progress bond or arrow
			tempBond = null;
			tempArrow = null;
		} else if (event.key === 'Delete' || event.key === 'Backspace') {
			deleteSelected();
		} else if ((event.metaKey || event.ctrlKey) && event.key === 'a') {
			event.preventDefault();
			selectAll();
		} else if ((event.metaKey || event.ctrlKey) && event.key === 'c') {
			event.preventDefault();
			copySelected();
		} else if ((event.metaKey || event.ctrlKey) && event.key === 'v') {
			event.preventDefault();
			pasteClipboard();
		} else if ((event.metaKey || event.ctrlKey) && event.key === 'z') {
			event.preventDefault();
			if (event.shiftKey) {
				redo();
			} else {
				undo();
			}
		}
	}

	function handleContextMenu(event) {
		event.preventDefault();
		contextMenu = { visible: true, x: event.clientX, y: event.clientY };
	}

	function hideContextMenu() {
		contextMenu.visible = false;
	}

	// Pan and zoom handlers
	function handleMouseDown(event) {
		if (event.button === 1 || (event.button === 0 && event.altKey)) {
			event.preventDefault();
			isPanning = true;
			lastPanPoint = { x: event.clientX, y: event.clientY };
			svgElement.style.cursor = 'grabbing';
		} else if (event.button === 0 && event.shiftKey && !event.altKey
				   && (selectedAtoms.size > 0 || selectedArrows.size > 0)) {
			// Shift+drag: move the selection from anywhere — works in any tool mode.
			// We record the start but don't begin the drag yet; mousemove applies a
			// threshold so that shift+click for selection still works normally.
			event.preventDefault();
			const coords = getCanvasCoordinates(event);
			shiftMoveStart = { clientX: event.clientX, clientY: event.clientY, canvasX: coords.x, canvasY: coords.y };
			justFinishedShiftDrag = false;
		} else if (event.button === 0 && selectedTool === 'select') {
			event.preventDefault();
			const coords = getCanvasCoordinates(event);
			isBoxSelecting = true;
			boxStart = { x: coords.x, y: coords.y };
			boxEnd = { x: coords.x, y: coords.y };
		} else if (event.button === 0 && selectedTool === 'export') {
			event.preventDefault();
			const coords = getCanvasCoordinates(event);
			isDrawingExportBox = true;
			exportBoxReady = false;
			exportBoxStart = { x: coords.x, y: coords.y };
			exportBoxEnd = { x: coords.x, y: coords.y };
		}
	}

	function handleMouseMove(event) {
		if (isPanning) {
			event.preventDefault();
			const dx = event.clientX - lastPanPoint.x;
			const dy = event.clientY - lastPanPoint.y;

			pan.x += dx / zoom;
			pan.y += dy / zoom;
			pan = { ...pan };

			lastPanPoint = { x: event.clientX, y: event.clientY };
			updateViewBox();
		} else if (arrowHandleDrag) {
			// Resize arrow by dragging one endpoint
			event.preventDefault();
			const coords = getCanvasCoordinates(event);
			arrows = arrows.map(arrow => {
				if (arrow.id !== arrowHandleDrag.arrowId) return arrow;
				if (arrowHandleDrag.handle === 'start') {
					return { ...arrow, startX: coords.x, startY: coords.y };
				} else {
					return { ...arrow, endX: coords.x, endY: coords.y };
				}
			});
		} else if (shiftMoveStart && !isDragging) {
			// Pending shift+drag — commit to a real drag once the mouse moves > 5px
			const dist = Math.hypot(event.clientX - shiftMoveStart.clientX, event.clientY - shiftMoveStart.clientY);
			if (dist > 5) {
				saveState();
				isDragging = true;
				draggedAtomId = null;
				dragStartCanvasX = shiftMoveStart.canvasX;
				dragStartCanvasY = shiftMoveStart.canvasY;

				dragAtomSnapshots.clear();
				selectedAtoms.forEach(id => {
					const a = atoms.find(a2 => a2.id === id);
					if (a) dragAtomSnapshots.set(id, { x: a.x, y: a.y });
				});
				dragArrowSnapshots.clear();
				selectedArrows.forEach(id => {
					const ar = arrows.find(a2 => a2.id === id);
					if (ar) dragArrowSnapshots.set(id, { startX: ar.startX, startY: ar.startY, endX: ar.endX, endY: ar.endY });
				});
				dragTextSnapshots.clear();
				selectedTexts.forEach(id => {
					const t = texts.find(t2 => t2.id === id);
					if (t) dragTextSnapshots.set(id, { x: t.x, y: t.y });
				});

				shiftMoveStart = null;
				justFinishedShiftDrag = true;
			}
		} else if (isDragging) {
			event.preventDefault();
			const coords = getCanvasCoordinates(event);

			let dx = coords.x - dragStartCanvasX;
			let dy = coords.y - dragStartCanvasY;

			// Snap based on anchor atom if there is one, otherwise free
			if (snapToGrid && gridEnabled && draggedAtomId) {
				const anchorSnap = dragAtomSnapshots.get(draggedAtomId);
				if (anchorSnap) {
					const snapped = snapToGridPoint(anchorSnap.x + dx, anchorSnap.y + dy);
					dx = snapped.x - anchorSnap.x;
					dy = snapped.y - anchorSnap.y;
				}
			}

			applyGroupDragDelta(dx, dy);
		} else if (isBoxSelecting) {
			event.preventDefault();
			const coords = getCanvasCoordinates(event);
			boxEnd = { x: coords.x, y: coords.y };
		} else if (isDrawingExportBox) {
			event.preventDefault();
			const coords = getCanvasCoordinates(event);
			exportBoxEnd = { x: coords.x, y: coords.y };
		}
	}

	function handleMouseUp(event) {
		if (isPanning) {
			isPanning = false;
			svgElement.style.cursor = 'default';
		} else if (shiftMoveStart) {
			// Mouse released without crossing drag threshold — just a shift+click, not a drag.
			// Let the click event on atoms/bonds handle selection toggling normally.
			shiftMoveStart = null;
			justFinishedShiftDrag = false;
		} else if (arrowHandleDrag) {
			arrowHandleDrag = null;
		} else if (isDragging) {
			isDragging = false;
			draggedAtomId = null;
			dragAtomSnapshots.clear();
			dragArrowSnapshots.clear();
			dragTextSnapshots.clear();
			// justFinishedShiftDrag stays true until the next click clears it
		} else if (isBoxSelecting) {
			isBoxSelecting = false;
			justFinishedBoxSelect = true;

			const minX = Math.min(boxStart.x, boxEnd.x);
			const maxX = Math.max(boxStart.x, boxEnd.x);
			const minY = Math.min(boxStart.y, boxEnd.y);
			const maxY = Math.max(boxStart.y, boxEnd.y);

			const selectedInBox = atoms.filter(atom =>
				atom.x >= minX && atom.x <= maxX && atom.y >= minY && atom.y <= maxY
			);
			const arrowsInBox = arrows.filter(arrow => isArrowInBox(arrow, minX, maxX, minY, maxY));
			const bondsInBox = bonds.filter(bond => isBondInBox(bond, minX, maxX, minY, maxY));
			const lonePairsInBox = lonePairs.filter(lonePair => isLonePairInBox(lonePair, minX, maxX, minY, maxY));
			const textsInBox = texts.filter(t => t.x >= minX && t.x <= maxX && t.y >= minY && t.y <= maxY);

			if (!event.shiftKey) {
				selectedAtoms.clear();
				selectedArrows.clear();
				selectedBonds.clear();
				selectedLonePairs.clear();
				selectedTexts.clear();
			}

			selectedInBox.forEach(atom => selectedAtoms.add(atom.id));
			arrowsInBox.forEach(arrow => selectedArrows.add(arrow.id));
			bondsInBox.forEach(bond => selectedBonds.add(bond.id));
			lonePairsInBox.forEach(lonePair => selectedLonePairs.add(lonePair.id));
			textsInBox.forEach(t => selectedTexts.add(t.id));
			selectedAtoms = new Set(selectedAtoms);
			selectedArrows = new Set(selectedArrows);
			selectedBonds = new Set(selectedBonds);
			selectedLonePairs = new Set(selectedLonePairs);
			selectedTexts = new Set(selectedTexts);

			atoms = atoms.map(atom => ({ ...atom, selected: selectedAtoms.has(atom.id) }));
		} else if (isDrawingExportBox) {
			isDrawingExportBox = false;
			if (Math.abs(exportBoxEnd.x - exportBoxStart.x) > 5 && Math.abs(exportBoxEnd.y - exportBoxStart.y) > 5) {
				exportBoxReady = true;
			}
		}
	}

	function exportToPNG() {
		const padding = 28;
		const scale = 3; // 3× resolution for crisp output

		const minX = Math.min(exportBoxStart.x, exportBoxEnd.x);
		const minY = Math.min(exportBoxStart.y, exportBoxEnd.y);
		const maxX = Math.max(exportBoxStart.x, exportBoxEnd.x);
		const maxY = Math.max(exportBoxStart.y, exportBoxEnd.y);

		const bx = minX - padding;
		const by = minY - padding;
		const bw = (maxX - minX) + padding * 2;
		const bh = (maxY - minY) + padding * 2;
		const outW = Math.round(bw * scale);
		const outH = Math.round(bh * scale);

		const svgClone = svgElement.cloneNode(true);
		svgClone.setAttribute('viewBox', `${bx} ${by} ${bw} ${bh}`);
		svgClone.setAttribute('width', outW);
		svgClone.setAttribute('height', outH);
		svgClone.removeAttribute('style');

		// Remove UI-only layers
		const gridGroup = svgClone.querySelector('#frankbond-grid');
		if (gridGroup) gridGroup.remove();
		const exportOverlay = svgClone.querySelector('#frankbond-export-overlay');
		if (exportOverlay) exportOverlay.remove();

		// White background
		const ns = 'http://www.w3.org/2000/svg';
		const bgRect = document.createElementNS(ns, 'rect');
		bgRect.setAttribute('x', bx);
		bgRect.setAttribute('y', by);
		bgRect.setAttribute('width', bw);
		bgRect.setAttribute('height', bh);
		bgRect.setAttribute('fill', 'white');
		svgClone.insertBefore(bgRect, svgClone.firstChild);

		const svgString = new XMLSerializer().serializeToString(svgClone);
		const svgBlob = new Blob([svgString], { type: 'image/svg+xml;charset=utf-8' });
		const url = URL.createObjectURL(svgBlob);

		const img = new Image();
		img.onload = () => {
			const canvas = document.createElement('canvas');
			canvas.width = outW;
			canvas.height = outH;
			const ctx = canvas.getContext('2d');
			ctx.fillStyle = 'white';
			ctx.fillRect(0, 0, outW, outH);
			ctx.drawImage(img, 0, 0, outW, outH);
			URL.revokeObjectURL(url);
			canvas.toBlob((pngBlob) => {
				const a = document.createElement('a');
				a.href = URL.createObjectURL(pngBlob);
				a.download = 'molecule.png';
				document.body.appendChild(a);
				a.click();
				document.body.removeChild(a);
			}, 'image/png');
		};
		img.onerror = () => URL.revokeObjectURL(url);
		img.src = url;
	}

	function handleWheel(event) {
		event.preventDefault();

		if (event.ctrlKey || event.metaKey) {
			const rect = svgElement.getBoundingClientRect();
			const mouseX = event.clientX - rect.left;
			const mouseY = event.clientY - rect.top;

			const zoomFactor = event.deltaY > 0 ? 0.9 : 1.1;
			const newZoom = Math.max(0.1, Math.min(zoom * zoomFactor, 5));

			const worldX = (mouseX / zoom) - pan.x;
			const worldY = (mouseY / zoom) - pan.y;

			zoom = newZoom;

			pan.x = (mouseX / zoom) - worldX;
			pan.y = (mouseY / zoom) - worldY;
			pan = { ...pan };
			updateViewBox();
		} else {
			pan.x -= event.deltaX / zoom;
			pan.y -= event.deltaY / zoom;
			pan = { ...pan };
			updateViewBox();
		}
	}

	// Touch handlers
	let touches = [];
	let initialDistance = 0;
	let initialZoom = 1;
	let initialPan = { x: 0, y: 0 };

	function handleTouchStart(event) {
		touches = Array.from(event.touches);

		if (touches.length === 2) {
			event.preventDefault();
			const touch1 = touches[0];
			const touch2 = touches[1];

			initialDistance = Math.sqrt(
				Math.pow(touch2.clientX - touch1.clientX, 2) +
				Math.pow(touch2.clientY - touch1.clientY, 2)
			);
			initialZoom = zoom;
			initialPan = { ...pan };
		} else if (touches.length === 1) {
			lastPanPoint = { x: touches[0].clientX, y: touches[0].clientY };
		}
	}

	function handleTouchMove(event) {
		event.preventDefault();
		touches = Array.from(event.touches);

		if (touches.length === 2) {
			const touch1 = touches[0];
			const touch2 = touches[1];

			const currentDistance = Math.sqrt(
				Math.pow(touch2.clientX - touch1.clientX, 2) +
				Math.pow(touch2.clientY - touch1.clientY, 2)
			);

			const zoomFactor = currentDistance / initialDistance;
			zoom = Math.max(0.1, Math.min(initialZoom * zoomFactor, 5));

			const centerX = (touch1.clientX + touch2.clientX) / 2;
			const centerY = (touch1.clientY + touch2.clientY) / 2;

			const rect = svgElement.getBoundingClientRect();
			const relativeCenterX = centerX - rect.left;
			const relativeCenterY = centerY - rect.top;

			pan.x = relativeCenterX - (relativeCenterX - initialPan.x) * (zoom / initialZoom);
			pan.y = relativeCenterY - (relativeCenterY - initialPan.y) * (zoom / initialZoom);
			pan = { ...pan };

			updateViewBox();
		} else if (touches.length === 1) {
			const dx = touches[0].clientX - lastPanPoint.x;
			const dy = touches[0].clientY - lastPanPoint.y;

			pan.x += dx / zoom;
			pan.y += dy / zoom;
			pan = { ...pan };

			lastPanPoint = { x: touches[0].clientX, y: touches[0].clientY };
			updateViewBox();
		}
	}

	function handleTouchEnd(event) {
		touches = Array.from(event.touches);
	}

	// --- AUTH & STRUCTURES ---
	async function checkAuth() {
		fsToken = localStorage.getItem('fs_token');
		if (!fsToken) return;

		try {
			const res = await fetch('https://frankstation.org/api/auth/me', {
				headers: { Authorization: `Bearer ${fsToken}` }
			});
			if (res.ok) {
				currentUser = await res.json();
				loadStructures();
			} else {
				fsToken = null;
				currentUser = null;
			}
		} catch {
			// Can't reach FrankStation auth — still allow drawing
		}
	}

	async function loadStructures() {
		if (!fsToken) return;
		structuresLoading = true;
		try {
			const res = await fetch(`${API_BASE}/structures`, {
				headers: { Authorization: `Bearer ${fsToken}` }
			});
			if (res.ok) {
				savedStructures = await res.json();
			}
		} catch (e) {
			console.error('Failed to load structures', e);
		} finally {
			structuresLoading = false;
		}
	}

	async function saveStructure() {
		if (!fsToken) {
			structureSaveError = 'You must be logged in to save structures.';
			return;
		}

		structureSaveError = '';
		const data = { atoms, bonds, arrows, lonePairs, bondlineMode };

		try {
			const res = await fetch(`${API_BASE}/structures`, {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json',
					Authorization: `Bearer ${fsToken}`
				},
				body: JSON.stringify({ name: structureName || 'Untitled', data })
			});

			if (res.ok) {
				const saved = await res.json();
				savedStructures = [saved, ...savedStructures];
				structureName = 'Untitled';
			} else {
				const err = await res.json();
				structureSaveError = err.error || 'Save failed';
			}
		} catch (e) {
			structureSaveError = 'Network error saving structure';
		}
	}

	async function deleteStructure(id) {
		if (!fsToken) return;
		try {
			const res = await fetch(`${API_BASE}/structures/${id}`, {
				method: 'DELETE',
				headers: { Authorization: `Bearer ${fsToken}` }
			});
			if (res.ok) {
				savedStructures = savedStructures.filter(s => s.id !== id);
			}
		} catch (e) {
			console.error('Failed to delete', e);
		}
	}

	async function loadStructure(id) {
		if (!fsToken) return;
		try {
			const res = await fetch(`${API_BASE}/structures/${id}`, {
				headers: { Authorization: `Bearer ${fsToken}` }
			});
			if (res.ok) {
				const record = await res.json();
				const d = record.data;
				saveState();
				atoms = d.atoms || [];
				bonds = d.bonds || [];
				arrows = d.arrows || [];
				lonePairs = d.lonePairs || [];
				if (d.bondlineMode !== undefined) bondlineMode = d.bondlineMode;
				// Rebuild graph
				moleculeGraph.nodes.clear();
				moleculeGraph.edges.clear();
				moleculeGraph.adjacency.clear();
				atoms.forEach(atom => {
					moleculeGraph.nodes.set(atom.id, atom);
					moleculeGraph.adjacency.set(atom.id, new Set());
				});
				bonds.forEach(bond => {
					moleculeGraph.edges.set(bond.id, bond);
					if (!moleculeGraph.adjacency.has(bond.atomId1)) moleculeGraph.adjacency.set(bond.atomId1, new Set());
					if (!moleculeGraph.adjacency.has(bond.atomId2)) moleculeGraph.adjacency.set(bond.atomId2, new Set());
					moleculeGraph.adjacency.get(bond.atomId1).add(bond.atomId2);
					moleculeGraph.adjacency.get(bond.atomId2).add(bond.atomId1);
				});
				structureName = record.name;
			}
		} catch (e) {
			console.error('Failed to load structure', e);
		}
	}

	async function copyStructureJSON(id) {
		if (!fsToken) return;
		try {
			const res = await fetch(`${API_BASE}/structures/${id}`, {
				headers: { Authorization: `Bearer ${fsToken}` }
			});
			if (res.ok) {
				const record = await res.json();
				await navigator.clipboard.writeText(JSON.stringify(record.data, null, 2));
			}
		} catch (e) {
			console.error('Failed to copy', e);
		}
	}

	function copyCurrentJSON() {
		const data = { atoms, bonds, arrows, lonePairs, bondlineMode };
		navigator.clipboard.writeText(JSON.stringify(data, null, 2));
	}

	function formatDate(iso) {
		return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
	}

	onMount(() => {
		document.addEventListener('keydown', handleKeyDown);
		document.addEventListener('click', hideContextMenu);
		checkAuth();
		return () => {
			document.removeEventListener('keydown', handleKeyDown);
			document.removeEventListener('click', hideContextMenu);
		};
	});
</script>

<svelte:head>
	<title>FrankBond — Chemical Drawing</title>
</svelte:head>

<div class="app">
	<div class="toolbar">
		<!-- MODE TOGGLE -->
		<div class="tool-group mode-toggle-group">
			<button
				class="mode-toggle-btn {bondlineMode ? '' : 'active'}"
				on:click={() => bondlineMode = false}
				title="Lewis Structure Mode: atoms shown as labeled circles"
			>
				Lewis
			</button>
			<button
				class="mode-toggle-btn {bondlineMode ? 'active' : ''}"
				on:click={() => { bondlineMode = true; if (gridType === 'square') gridType = 'hexagonal'; }}
				title="Bondline/Skeletal Mode: carbons implied at vertices"
			>
				Bondline
			</button>
		</div>

		<div class="tool-group">
			<h3>Tools</h3>
			<button
				class="tool-btn {selectedTool === 'select' ? 'active' : ''}"
				on:click={() => selectedTool = 'select'}
			>
				Select
			</button>
			<button
				class="tool-btn {selectedTool === 'atom' ? 'active' : ''}"
				on:click={() => selectedTool = 'atom'}
			>
				{bondlineMode ? 'Add Vertex' : 'Add Atom'}
			</button>
			<button
				class="tool-btn {selectedTool === 'bond' ? 'active' : ''}"
				on:click={() => selectedTool = 'bond'}
			>
				Draw Bond
			</button>
			<button
				class="tool-btn {selectedTool === 'arrow' ? 'active' : ''}"
				on:click={() => selectedTool = 'arrow'}
			>
				Reaction Arrow
			</button>
			<button
				class="tool-btn {selectedTool === 'text' ? 'active' : ''}"
				on:click={() => selectedTool = 'text'}
			>
				Add Text
			</button>
			{#if !bondlineMode}
			<button
				class="tool-btn {selectedTool === 'lonepair' ? 'active' : ''}"
				on:click={() => selectedTool = 'lonepair'}
			>
				Lone Pair
			</button>
			{/if}
			<button
				class="tool-btn {selectedTool === 'export' ? 'active' : ''}"
				on:click={() => { selectedTool = 'export'; exportBoxReady = false; }}
			>
				Export PNG
			</button>
			{#if exportBoxReady && selectedTool === 'export'}
				<button class="export-confirm-btn" on:click={exportToPNG}>
					↓ Download PNG
				</button>
			{/if}
		</div>

		<div class="tool-group">
			<h3>Elements</h3>
			<div class="element-grid">
				{#each elements as element}
					<button
						class="element-btn {selectedElement === element ? 'active' : ''}"
						style="color: {getAtomColor(element)}; border-color: {selectedElement === element ? getAtomColor(element) : '#ccc'};"
						on:click={() => selectedElement = element}
					>
						{element}
					</button>
				{/each}
			</div>
			{#if bondlineMode}
				<p class="mode-hint">In bondline mode, C atoms are implied at vertices. Select a heteroatom (O, N, etc.) to place labeled atoms.</p>
			{/if}
		</div>

		{#if bondlineMode}
		<div class="tool-group">
			<h3>Functional Groups</h3>
			<div class="element-grid">
				<button
					class="element-btn {selectedElement === 'OH' ? 'active' : ''}"
					style="color: #ff0000; border-color: {selectedElement === 'OH' ? '#ff0000' : '#ccc'};"
					on:click={() => selectedElement = 'OH'}
				>
					OH
				</button>
				<button
					class="element-btn {selectedElement === 'MeO' ? 'active' : ''}"
					style="color: #ff0000; border-color: {selectedElement === 'MeO' ? '#ff0000' : '#ccc'};"
					on:click={() => selectedElement = 'MeO'}
				>
					MeO
				</button>
			</div>
		</div>
		{/if}

		<div class="tool-group">
			<h3>Grid</h3>
			<label class="checkbox-label">
				<input
					type="checkbox"
					bind:checked={gridEnabled}
					on:change={() => updateViewBox()}
				/>
				Show Grid
			</label>

			<div class="grid-controls" class:disabled={!gridEnabled}>
				<label class="radio-label">
					<input
						type="radio"
						bind:group={gridType}
						value="square"
						disabled={!gridEnabled}
					/>
					Square
				</label>
				<label class="radio-label">
					<input
						type="radio"
						bind:group={gridType}
						value="hexagonal"
						disabled={!gridEnabled}
					/>
					Hexagonal <span class="grid-hint">(0°/60°/120°)</span>
				</label>
				<label class="radio-label">
					<input
						type="radio"
						bind:group={gridType}
						value="chair"
						disabled={!gridEnabled}
					/>
					Chair <span class="grid-hint">(30°/90°/150°)</span>
				</label>

				<label class="checkbox-label">
					<input
						type="checkbox"
						bind:checked={snapToGrid}
						disabled={!gridEnabled}
					/>
					Snap to Grid
				</label>

				<label class="range-label">
					Grid Size: {gridSize}px
					<input
						type="range"
						min="20"
						max="80"
						bind:value={gridSize}
						disabled={!gridEnabled}
						on:input={() => updateViewBox()}
					/>
				</label>
			</div>
		</div>

		<div class="tool-group">
			<h3>View</h3>
			<button class="tool-btn" on:click={() => { zoom = Math.min(zoom * 1.5, 5); updateViewBox(); }}>
				Zoom In (+)
			</button>
			<button class="tool-btn" on:click={() => { zoom = Math.max(zoom / 1.5, 0.1); updateViewBox(); }}>
				Zoom Out (-)
			</button>
			<button class="tool-btn" on:click={() => { zoom = 1; pan = { x: 0, y: 0 }; updateViewBox(); }}>
				Reset View
			</button>
			<div class="zoom-info">Zoom: {Math.round(zoom * 100)}%</div>
		</div>

		<div class="tool-group">
			<h3>Actions</h3>
			<button class="tool-btn" on:click={undo} disabled={undoStack.length === 0}>Undo (⌘Z)</button>
			<button class="tool-btn" on:click={redo} disabled={redoStack.length === 0}>Redo (⌘⇧Z)</button>
			<div class="copy-paste-row">
				<button class="tool-btn" on:click={copySelected} title="Copy selected (⌘C)">Copy</button>
				<button class="tool-btn" on:click={pasteClipboard} disabled={!clipboard} title="Paste (⌘V)">Paste</button>
			</div>
			<button class="action-btn" on:click={deleteSelected}>Delete Selected</button>
			<button class="action-btn" on:click={() => {
				saveState();
				atoms = []; bonds = []; arrows = []; lonePairs = [];
				selectedAtoms.clear(); selectedArrows.clear(); selectedBonds.clear(); selectedLonePairs.clear();
				selectedAtoms = new Set(); selectedArrows = new Set(); selectedBonds = new Set(); selectedLonePairs = new Set();
			}}>Clear All</button>
			<button class="tool-btn" on:click={copyCurrentJSON} title="Copy current drawing as JSON">Copy JSON</button>
		</div>

		<!-- MY STRUCTURES -->
		<div class="tool-group">
			<h3>
				My Structures
				{#if currentUser}
					<span class="user-badge">{currentUser.username}</span>
				{/if}
			</h3>

			{#if !currentUser}
				<p class="auth-notice">
					<a href="https://frankstation.org" target="_blank" rel="noopener">Log in to FrankStation</a> to save & load structures.
				</p>
			{:else}
				<div class="save-row">
					<input
						class="name-input"
						type="text"
						placeholder="Structure name…"
						bind:value={structureName}
						on:keydown={(e) => { if (e.key === 'Enter') saveStructure(); }}
					/>
					<button class="save-btn" on:click={saveStructure}>Save</button>
				</div>
				{#if structureSaveError}
					<p class="save-error">{structureSaveError}</p>
				{/if}

				<button
					class="tool-btn"
					on:click={() => { showStructuresPanel = !showStructuresPanel; if (showStructuresPanel) loadStructures(); }}
				>
					{showStructuresPanel ? 'Hide' : 'Show'} Saved ({savedStructures.length})
				</button>

				{#if showStructuresPanel}
					<div class="structures-list">
						{#if structuresLoading}
							<p class="loading">Loading…</p>
						{:else if savedStructures.length === 0}
							<p class="empty">No saved structures yet.</p>
						{:else}
							{#each savedStructures as s}
								<div class="structure-card">
									<div class="structure-name">{s.name}</div>
									<div class="structure-date">{formatDate(s.updated_at)}</div>
									<div class="structure-actions">
										<button class="card-btn load-btn" on:click={() => loadStructure(s.id)}>Load</button>
										<button class="card-btn copy-btn" on:click={() => copyStructureJSON(s.id)}>Copy JSON</button>
										<button class="card-btn del-btn" on:click={() => deleteStructure(s.id)}>×</button>
									</div>
								</div>
							{/each}
						{/if}
					</div>
				{/if}
			{/if}
		</div>

		<div class="tool-group">
			<h3>Education</h3>
			<button class="tool-btn" on:click={() => showEducationalModal = true}>Chemistry Guide</button>
		</div>

		<div class="instructions">
			<strong>Controls:</strong><br>
			• Two-finger pan/zoom on trackpad<br>
			• Ctrl/Cmd + scroll to zoom<br>
			• Alt + drag to pan<br>
			• Middle mouse to pan<br>
			• Click bonds to cycle types
		</div>
	</div>

	<div class="drawing-area">
		<svg
			bind:this={svgElement}
			width="100%"
			height="100%"
			viewBox="{viewBox.x} {viewBox.y} {viewBox.width} {viewBox.height}"
			preserveAspectRatio="xMidYMid meet"
			on:click={(e) => { handleSVGClick(e); hideContextMenu(); }}
			on:mousedown={handleMouseDown}
			on:mousemove={(e) => { handleMouseMove(e); handleSVGMouseMove(e); }}
			on:mouseleave={handleSVGMouseLeave}
			on:mouseup={handleMouseUp}
			on:wheel={handleWheel}
			on:contextmenu={handleContextMenu}
			on:touchstart={handleTouchStart}
			on:touchmove={handleTouchMove}
			on:touchend={handleTouchEnd}
		>
			<!-- Grid Points -->
			{#if gridEnabled}
				<g id="frankbond-grid">
					{#each gridPoints as point}
						<circle
							cx={point.x}
							cy={point.y}
							r="1.5"
							fill="#cccccc"
							opacity="0.5"
							pointer-events="none"
						/>
					{/each}
				</g>
			{/if}

			<!-- Bonds -->
			{#each bonds as bond}
				{#each getBondPaths(bond) as path}
					<path
						d={path}
						stroke={selectedBonds.has(bond.id) ? "#0066cc" : "#111111"}
						stroke-width={selectedBonds.has(bond.id) ? "3" : "2"}
						stroke-linecap="round"
						fill="none"
						on:click={(e) => {
							if (selectedTool === 'bond') {
								saveState();
								const currentTypeIndex = bondTypes.indexOf(bond.type);
								const nextTypeIndex = (currentTypeIndex + 1) % bondTypes.length;
								bonds = bonds.map(b => b.id === bond.id ? { ...b, type: bondTypes[nextTypeIndex] } : b);
							} else if (selectedTool === 'select') {
								e.stopPropagation();
								if (e.shiftKey) {
									if (selectedBonds.has(bond.id)) {
										selectedBonds.delete(bond.id);
									} else {
										selectedBonds.add(bond.id);
									}
								} else {
									selectedBonds.clear();
									selectedBonds.add(bond.id);
								}
								selectedBonds = new Set(selectedBonds);
							}
						}}
						style="cursor: pointer;"
					/>
				{/each}
			{/each}

			<!-- Temporary bond while drawing -->
			{#if tempBond}
				<path
					d="M {tempBond.x} {tempBond.y} L {debugCursor.x} {debugCursor.y}"
					stroke="#999999"
					stroke-width="2"
					stroke-dasharray="5,5"
					fill="none"
					pointer-events="none"
				/>
			{/if}

			<!-- Arrows -->
			{#each arrows as arrow}
				<defs>
					<marker
						id="arrowhead-{arrow.id}"
						markerWidth="10"
						markerHeight="7"
						refX="9"
						refY="3.5"
						orient="auto"
					>
						<polygon points="0 0, 10 3.5, 0 7" fill="#000000" />
					</marker>
				</defs>
				<!-- Wider invisible hit area for easier selection -->
				<line
					x1={arrow.startX}
					y1={arrow.startY}
					x2={arrow.endX}
					y2={arrow.endY}
					stroke="transparent"
					stroke-width="12"
					style="cursor: {selectedTool === 'select' ? (selectedArrows.has(arrow.id) ? 'grab' : 'pointer') : 'pointer'};"
					on:mousedown={(e) => {
						if (selectedTool === 'select' && selectedArrows.has(arrow.id) && e.button === 0 && !e.altKey) {
							startArrowBodyDrag(arrow.id, e);
						}
					}}
					on:click={(e) => {
						if (selectedTool === 'select') {
							e.stopPropagation();
							if (e.shiftKey) {
								if (selectedArrows.has(arrow.id)) { selectedArrows.delete(arrow.id); } else { selectedArrows.add(arrow.id); }
							} else {
								selectedArrows.clear();
								selectedArrows.add(arrow.id);
							}
							selectedArrows = new Set(selectedArrows);
						}
					}}
				/>
				<!-- Visible arrow line -->
				<line
					x1={arrow.startX}
					y1={arrow.startY}
					x2={arrow.endX}
					y2={arrow.endY}
					stroke={selectedArrows.has(arrow.id) ? "#0066cc" : "#000000"}
					stroke-width={selectedArrows.has(arrow.id) ? "3" : "2.5"}
					marker-end="url(#arrowhead-{arrow.id})"
					pointer-events="none"
				/>
				<!-- Endpoint handles when selected -->
				{#if selectedArrows.has(arrow.id)}
					<!-- Start handle (hollow circle) -->
					<circle
						cx={arrow.startX}
						cy={arrow.startY}
						r="6"
						fill="white"
						stroke="#0066cc"
						stroke-width="2"
						style="cursor: crosshair;"
						on:mousedown={(e) => startArrowHandleDrag(arrow.id, 'start', e)}
					/>
					<!-- End handle (filled circle) -->
					<circle
						cx={arrow.endX}
						cy={arrow.endY}
						r="6"
						fill="#0066cc"
						stroke="#0055aa"
						stroke-width="1.5"
						style="cursor: crosshair;"
						on:mousedown={(e) => startArrowHandleDrag(arrow.id, 'end', e)}
					/>
				{/if}
			{/each}

			<!-- Temporary arrow while drawing -->
			{#if tempArrow}
				<defs>
					<marker id="temp-arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
						<polygon points="0 0, 10 3.5, 0 7" fill="#999999" />
					</marker>
				</defs>
				<line
					x1={tempArrow.startX}
					y1={tempArrow.startY}
					x2={tempArrow.endX}
					y2={tempArrow.endY}
					stroke="#999999"
					stroke-width="3"
					stroke-dasharray="5,5"
					marker-end="url(#temp-arrowhead)"
				/>
			{/if}

			<!-- Atoms -->
			{#each atoms as atom}
				<g>
					{#if bondlineMode}
						<!-- BONDLINE MODE rendering -->
						{#if atom.element === 'C'}
							<!-- Carbon: just a small hit-target dot, no label -->
							<circle
								cx={atom.x}
								cy={atom.y}
								r="6"
								fill="transparent"
								stroke={atom.selected ? "#0066cc" : "transparent"}
								stroke-width={atom.selected ? "2" : "0"}
								on:mousedown={(e) => { if (isPanning) return; if (selectedTool === 'select' && selectedAtoms.has(atom.id)) startAtomDrag(atom.id, e); }}
								on:click={(e) => {
									if (isPanning || isDragging) return;
									e.stopPropagation();
									if (selectedTool === 'bond') {
										if (tempBond) { completeBond(atom.id, e); } else { startBond(atom.id, e); }
									} else if (selectedTool === 'select') {
										selectAtom(atom.id, e.shiftKey);
									}
								}}
								style="cursor: {selectedTool === 'select' && selectedAtoms.has(atom.id) ? 'grab' : 'pointer'};"
							/>
							<!-- Small visible dot at vertex when selected or hovered -->
							{#if atom.selected}
								<circle cx={atom.x} cy={atom.y} r="4" fill="#0066cc" opacity="0.7" pointer-events="none" />
							{/if}
						{:else}
							<!-- Heteroatom in bondline mode: text label, white bg pill -->
							<rect
								x={atom.x - (atom.element.length > 2 ? 19 : atom.element.length > 1 ? 14 : 9)}
								y={atom.y - 10}
								width={atom.element.length > 2 ? 38 : atom.element.length > 1 ? 28 : 18}
								height="20"
								rx="3"
								fill="white"
								stroke={atom.selected ? "#0066cc" : "none"}
								stroke-width={atom.selected ? "2" : "0"}
								pointer-events="none"
							/>
							{#if atom.element === 'OH'}
								<text
									x={atom.x}
									y={atom.y + 5}
									text-anchor="middle"
									font-family="Arial, sans-serif"
									font-size="14"
									font-weight="bold"
									pointer-events="none"
								><tspan fill="#ff0000">O</tspan><tspan fill="#444444">H</tspan></text>
							{:else if atom.element === 'MeO'}
								<text
									x={atom.x}
									y={atom.y + 5}
									text-anchor="middle"
									font-family="Arial, sans-serif"
									font-size="14"
									font-weight="bold"
									pointer-events="none"
								><tspan fill="#444444">Me</tspan><tspan fill="#ff0000">O</tspan></text>
							{:else}
								<text
									x={atom.x}
									y={atom.y + 5}
									text-anchor="middle"
									font-family="Arial, sans-serif"
									font-size="14"
									font-weight="bold"
									fill={getBondlineLabelColor(atom.element)}
									pointer-events="none"
								>
									{atom.element}
								</text>
							{/if}
							<!-- Invisible hit area -->
							<rect
								x={atom.x - 16}
								y={atom.y - 12}
								width="32"
								height="24"
								fill="transparent"
								on:mousedown={(e) => { if (isPanning) return; if (selectedTool === 'select' && selectedAtoms.has(atom.id)) startAtomDrag(atom.id, e); }}
								on:click={(e) => {
									if (isPanning || isDragging) return;
									e.stopPropagation();
									if (selectedTool === 'bond') {
										if (tempBond) { completeBond(atom.id, e); } else { startBond(atom.id, e); }
									} else if (selectedTool === 'select') {
										selectAtom(atom.id, e.shiftKey);
									} else if (selectedTool === 'lonepair') {
										const existingPairs = lonePairs.filter(lp => lp.atomId === atom.id);
										const angle = existingPairs.length * (Math.PI / 2);
										addLonePair(atom.id, angle);
									}
								}}
								style="cursor: pointer;"
							/>
						{/if}
					{:else}
						<!-- LEWIS MODE rendering -->
						<circle
							cx={atom.x}
							cy={atom.y}
							r="15"
							fill={getAtomColor(atom.element)}
							stroke={atom.selected ? "#0066cc" : "#333333"}
							stroke-width={atom.selected ? "3" : "1"}
							on:mousedown={(e) => {
								if (isPanning) return;
								if (selectedTool === 'select' && selectedAtoms.has(atom.id)) {
									startAtomDrag(atom.id, e);
								}
							}}
							on:click={(e) => {
								if (isPanning || isDragging) return;
								e.stopPropagation();
								if (selectedTool === 'bond') {
									if (tempBond) {
										completeBond(atom.id, e);
									} else {
										startBond(atom.id, e);
									}
								} else if (selectedTool === 'select') {
									selectAtom(atom.id, e.shiftKey);
								} else if (selectedTool === 'lonepair') {
									const existingPairs = lonePairs.filter(lp => lp.atomId === atom.id);
									const angle = existingPairs.length * (Math.PI / 2);
									addLonePair(atom.id, angle);
								}
							}}
							style="cursor: {selectedTool === 'select' && selectedAtoms.has(atom.id) ? 'grab' : 'pointer'};"
						/>
						<text
							x={atom.x}
							y={atom.y + 5}
							text-anchor="middle"
							font-family="Arial, sans-serif"
							font-size="13"
							font-weight="bold"
							fill={atom.element === 'S' ? '#000' : '#fff'}
							pointer-events="none"
						>
							{atom.element}
						</text>
					{/if}
				</g>
			{/each}

			<!-- Lone Pairs -->
			{#each lonePairs as lonePair}
				{@const position = getLonePairPosition(lonePair.atomId, lonePair.angle)}
				<g
					on:click={(e) => {
						if (selectedTool === 'select') {
							e.stopPropagation();
							if (e.shiftKey) {
								if (selectedLonePairs.has(lonePair.id)) {
									selectedLonePairs.delete(lonePair.id);
								} else {
									selectedLonePairs.add(lonePair.id);
								}
							} else {
								selectedLonePairs.clear();
								selectedLonePairs.add(lonePair.id);
							}
							selectedLonePairs = new Set(selectedLonePairs);
						}
					}}
					style="cursor: pointer;"
				>
					<circle
						cx={position.x - 3}
						cy={position.y}
						r="2"
						fill={selectedLonePairs.has(lonePair.id) ? "#0066cc" : "#000000"}
					/>
					<circle
						cx={position.x + 3}
						cy={position.y}
						r="2"
						fill={selectedLonePairs.has(lonePair.id) ? "#0066cc" : "#000000"}
					/>
				</g>
			{/each}

			<!-- Text annotations -->
			{#each texts as t}
				{#if !editingText || editingText.id !== t.id}
					{@const lineHeight = Math.round(t.fontSize * 1.35)}
					{@const lines = t.text.split('\n')}
					{@const hitW = Math.max(...lines.map(l => l.length || 1)) * t.fontSize * 0.62 + 12}
					{@const hitH = t.fontSize + (lines.length - 1) * lineHeight + 10}
					<g>
						<!-- Selection indicator -->
						{#if selectedTexts.has(t.id)}
							<rect
								x={t.x - 4} y={t.y - 4}
								width={hitW} height={hitH}
								fill="rgba(0,102,204,0.08)"
								stroke="#0066cc" stroke-width="1" stroke-dasharray="4,3" rx="2"
								pointer-events="none"
							/>
						{/if}
						<!-- Text lines (visual only) -->
						{#each lines as line, i}
							<text
								x={t.x}
								y={t.y + t.fontSize + i * lineHeight}
								font-family="Arial, sans-serif"
								font-size={t.fontSize}
								fill={selectedTexts.has(t.id) ? "#0066cc" : "#111111"}
								pointer-events="none"
							>{line}</text>
						{/each}
						<!-- Transparent hit area — receives all pointer events -->
						<rect
							x={t.x - 4} y={t.y - 4}
							width={hitW} height={hitH}
							fill="transparent"
							on:mousedown={(e) => {
								if (selectedTool !== 'select' || isPanning) return;
								if (!selectedTexts.has(t.id)) selectedTexts = new Set([t.id]);
								e.stopPropagation();
								saveState();
								isDragging = true;
								draggedAtomId = null;
								const coords = getCanvasCoordinates(e);
								dragStartCanvasX = coords.x;
								dragStartCanvasY = coords.y;
								dragAtomSnapshots.clear();
								selectedAtoms.forEach(id => { const a = atoms.find(a2 => a2.id === id); if (a) dragAtomSnapshots.set(id, { x: a.x, y: a.y }); });
								dragArrowSnapshots.clear();
								selectedArrows.forEach(id => { const ar = arrows.find(a2 => a2.id === id); if (ar) dragArrowSnapshots.set(id, { startX: ar.startX, startY: ar.startY, endX: ar.endX, endY: ar.endY }); });
								dragTextSnapshots.clear();
								selectedTexts.forEach(id => { const tx = texts.find(t2 => t2.id === id); if (tx) dragTextSnapshots.set(id, { x: tx.x, y: tx.y }); });
							}}
							on:click={(e) => {
								if (isPanning || isDragging) return;
								e.stopPropagation();
								if (selectedTool === 'select') {
									if (e.detail >= 2) {
										startEditText(t.id);
									} else if (e.shiftKey) {
										if (selectedTexts.has(t.id)) { selectedTexts.delete(t.id); } else { selectedTexts.add(t.id); }
										selectedTexts = new Set(selectedTexts);
									} else {
										selectedTexts = new Set([t.id]);
									}
								}
							}}
							style="cursor: {selectedTool === 'select' ? (selectedTexts.has(t.id) ? 'grab' : 'pointer') : 'default'};"
						/>
					</g>
				{/if}
			{/each}

			<!-- Box selection rectangle -->
			{#if isBoxSelecting}
				<rect
					x={Math.min(boxStart.x, boxEnd.x)}
					y={Math.min(boxStart.y, boxEnd.y)}
					width={Math.abs(boxEnd.x - boxStart.x)}
					height={Math.abs(boxEnd.y - boxStart.y)}
					fill="rgba(0, 102, 204, 0.1)"
					stroke="#0066cc"
					stroke-width="1"
					stroke-dasharray="5,5"
					pointer-events="none"
				/>
			{/if}

			<!-- Export bounding box overlay -->
			{#if isDrawingExportBox || exportBoxReady}
				<g id="frankbond-export-overlay" pointer-events="none">
					<rect
						x={Math.min(exportBoxStart.x, exportBoxEnd.x)}
						y={Math.min(exportBoxStart.y, exportBoxEnd.y)}
						width={Math.abs(exportBoxEnd.x - exportBoxStart.x)}
						height={Math.abs(exportBoxEnd.y - exportBoxStart.y)}
						fill="rgba(16, 185, 129, 0.07)"
						stroke="#10b981"
						stroke-width="1.5"
						stroke-dasharray="7,4"
					/>
				</g>
			{/if}

			<!-- Debug cursor indicator -->
			{#if debugCursor.visible}
				<circle cx={debugCursor.x} cy={debugCursor.y} r="3" fill="rgba(255,0,0,0.5)" pointer-events="none" />
			{/if}
		</svg>
	</div>
</div>

<!-- Text editing overlay -->
{#if editingText}
	<div
		class="text-editor-overlay"
		style="left: {textEditScreenPos.x}px; top: {textEditScreenPos.y}px;"
	>
		<textarea
			bind:this={textInputEl}
			bind:value={editInputValue}
			rows="3"
			placeholder="Type text… (Enter to confirm, Esc to cancel)"
			style="font-size: {editingText.fontSize}px;"
			on:keydown={(e) => {
				if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); commitTextEdit(); }
				if (e.key === 'Escape') cancelTextEdit();
			}}
			on:blur={commitTextEdit}
		/>
	</div>
{/if}

<!-- Custom Context Menu -->
{#if contextMenu.visible}
	<div
		class="context-menu"
		style="left: {contextMenu.x}px; top: {contextMenu.y}px;"
		on:click|stopPropagation
	>
		<div class="context-item {undoStack.length === 0 ? 'disabled' : ''}" on:click={() => { if (undoStack.length > 0) { undo(); hideContextMenu(); } }}>Undo (⌘Z)</div>
		<div class="context-item {redoStack.length === 0 ? 'disabled' : ''}" on:click={() => { if (redoStack.length > 0) { redo(); hideContextMenu(); } }}>Redo (⌘⇧Z)</div>
		<hr class="context-divider">
		<div class="context-item" on:click={() => { selectAll(); hideContextMenu(); }}>Select All (⌘A)</div>
		<div class="context-item" on:click={() => { copySelected(); hideContextMenu(); }}>Copy (⌘C)</div>
		<div class="context-item {!clipboard ? 'disabled' : ''}" on:click={() => { if (clipboard) { pasteClipboard(); hideContextMenu(); } }}>Paste (⌘V)</div>
		<div class="context-item" on:click={() => { deleteSelected(); hideContextMenu(); }}>Delete Selected</div>
		<hr class="context-divider">
		<div class="context-item" on:click={() => { saveState(); atoms = []; bonds = []; arrows = []; lonePairs = []; texts = []; selectedAtoms.clear(); selectedArrows.clear(); selectedBonds.clear(); selectedLonePairs.clear(); selectedTexts.clear(); hideContextMenu(); }}>Clear All</div>
	</div>
{/if}

<!-- Educational Modal -->
{#if showEducationalModal}
	<div class="modal-overlay" on:click={() => showEducationalModal = false}>
		<div class="modal-content" on:click|stopPropagation>
			<div class="modal-header">
				<h2>Organic Chemistry Guide</h2>
				<button class="close-btn" on:click={() => showEducationalModal = false}>×</button>
			</div>

			<div class="modal-body">
				<div class="info-section">
					<h3>Bondline (Skeletal) Structures</h3>
					<div class="structure-grid">
						<div class="structure-item">
							<strong>Carbon atoms</strong> are implied at every vertex and line end — not drawn explicitly
						</div>
						<div class="structure-item">
							<strong>Heteroatoms</strong> (O, N, S, etc.) are always shown with their symbol
						</div>
						<div class="structure-item">
							<strong>Hydrogen atoms</strong> are implicit on carbon — shown explicitly on heteroatoms
						</div>
						<div class="structure-item">
							<strong>Use hexagonal grid</strong> for proper 120° bond angles (zigzag chains, rings)
						</div>
					</div>
				</div>

				<div class="info-section">
					<h3>Lewis Structures</h3>
					<div class="structure-grid">
						<div class="structure-item">
							<strong>All atoms shown</strong> as labeled circles with element symbol
						</div>
						<div class="structure-item">
							<strong>Lone pairs</strong> can be added to atoms using the Lone Pair tool
						</div>
						<div class="structure-item">
							<strong>Bond types</strong> cycle single → double → triple by clicking a bond in Bond mode
						</div>
					</div>
				</div>

				<div class="info-section">
					<h3>Structure & Bonding Fundamentals</h3>
					<div class="structure-grid">
						<div class="structure-item">
							<strong>Resonance:</strong> Multiple valid electron arrangements (benzene, enolates, carbocations)
						</div>
						<div class="structure-item">
							<strong>Hybridization:</strong> sp³ (tetrahedral), sp² (trigonal planar), sp (linear)
						</div>
						<div class="structure-item">
							<strong>VSEPR:</strong> Electron pair repulsion determines molecular geometry
						</div>
					</div>
				</div>

				<div class="info-section">
					<h3>Electronegativity Trend</h3>
					<div class="trend-grid">
						<div class="trend-item">
							<strong>F &gt; O &gt; N &gt; Cl &gt; Br &gt; I &gt; S &gt; C &gt; H</strong><br>
							<em>Higher electronegativity = stronger electron pull. δ+C—δ-O, δ+C—δ-N, δ+C—δ-X.</em>
						</div>
					</div>
				</div>

				<div class="info-section">
					<h3>SN1 vs SN2</h3>
					<div class="mechanism-grid">
						<div class="mechanism-item sn1">
							<h4>SN1</h4>
							<p><strong>Rate:</strong> [R-X] only</p>
							<p><strong>Steps:</strong> 2 (carbocation intermediate)</p>
							<p><strong>Stereo:</strong> Racemization</p>
							<p><strong>Substrate:</strong> 3° &gt; 2° &gt;&gt; 1°</p>
							<p><strong>Solvent:</strong> Polar protic</p>
						</div>
						<div class="mechanism-item sn2">
							<h4>SN2</h4>
							<p><strong>Rate:</strong> [R-X][Nu-]</p>
							<p><strong>Steps:</strong> 1 (backside attack)</p>
							<p><strong>Stereo:</strong> Inversion</p>
							<p><strong>Substrate:</strong> 1° &gt; 2° &gt;&gt; 3°</p>
							<p><strong>Solvent:</strong> Polar aprotic</p>
						</div>
					</div>
				</div>
			</div>
		</div>
	</div>
{/if}

<style>
	.app {
		display: flex;
		height: 100vh;
		font-family: Arial, sans-serif;
		user-select: none;
		-webkit-user-select: none;
	}

	.toolbar {
		width: 240px;
		background-color: #f5f5f5;
		padding: 12px;
		border-right: 1px solid #ddd;
		overflow-y: auto;
		flex-shrink: 0;
	}

	/* Mode toggle */
	.mode-toggle-group {
		display: flex;
		gap: 0;
		margin-bottom: 16px;
	}

	.mode-toggle-btn {
		flex: 1;
		padding: 8px 4px;
		border: 1px solid #aaa;
		background: #fff;
		cursor: pointer;
		font-size: 13px;
		font-weight: bold;
		color: #555;
	}

	.mode-toggle-btn:first-child {
		border-radius: 4px 0 0 4px;
		border-right: none;
	}

	.mode-toggle-btn:last-child {
		border-radius: 0 4px 4px 0;
	}

	.mode-toggle-btn.active {
		background: #0066cc;
		color: white;
		border-color: #0055aa;
	}

	.tool-group {
		margin-bottom: 20px;
	}

	.tool-group h3 {
		margin: 0 0 8px 0;
		color: #333;
		font-size: 13px;
		text-transform: uppercase;
		letter-spacing: 0.5px;
		display: flex;
		align-items: center;
		gap: 6px;
	}

	.user-badge {
		font-size: 11px;
		font-weight: normal;
		background: #0066cc;
		color: white;
		padding: 1px 6px;
		border-radius: 8px;
		text-transform: none;
		letter-spacing: 0;
	}

	.tool-btn, .action-btn {
		display: block;
		width: 100%;
		padding: 8px 10px;
		margin-bottom: 4px;
		border: 1px solid #ccc;
		background-color: #fff;
		cursor: pointer;
		border-radius: 4px;
		font-size: 13px;
		text-align: left;
	}

	.tool-btn:hover, .action-btn:hover {
		background-color: #f0f0f0;
	}

	.tool-btn.active {
		background-color: #0066cc;
		color: white;
		border-color: #0055aa;
	}

	.text-editor-overlay {
		position: fixed;
		z-index: 1000;
		transform: translateY(-4px);
	}

	.text-editor-overlay textarea {
		min-width: 160px;
		padding: 4px 6px;
		border: 2px solid #0066cc;
		border-radius: 4px;
		background: rgba(255, 255, 255, 0.97);
		font-family: Arial, sans-serif;
		resize: both;
		outline: none;
		box-shadow: 0 2px 8px rgba(0,0,0,0.2);
		line-height: 1.35;
	}

	.export-confirm-btn {
		display: block;
		width: 100%;
		padding: 8px 10px;
		margin-bottom: 4px;
		background-color: #10b981;
		color: white;
		border: 1px solid #059669;
		border-radius: 4px;
		cursor: pointer;
		font-size: 13px;
		font-weight: 600;
		text-align: left;
	}

	.export-confirm-btn:hover {
		background-color: #059669;
	}

	.tool-btn:disabled {
		opacity: 0.45;
		cursor: not-allowed;
	}

	.element-grid {
		display: grid;
		grid-template-columns: repeat(5, 1fr);
		gap: 3px;
		margin-bottom: 6px;
	}

	.element-btn {
		padding: 6px 2px;
		border: 1px solid #ccc;
		background: white;
		cursor: pointer;
		border-radius: 3px;
		font-weight: bold;
		font-size: 11px;
		text-align: center;
	}

	.element-btn:hover { opacity: 0.7; }
	.element-btn.active { border-width: 2px; background: #f0f7ff; }

	.mode-hint {
		font-size: 11px;
		color: #888;
		margin: 4px 0 0;
		line-height: 1.4;
	}

	.drawing-area {
		flex: 1;
		background-color: white;
		overflow: hidden;
	}

	svg {
		background-color: white;
		touch-action: none;
		user-select: none;
	}

	.copy-paste-row {
		display: flex;
		gap: 4px;
		margin-bottom: 4px;
	}

	.copy-paste-row .tool-btn {
		flex: 1;
		margin-bottom: 0;
		text-align: center;
	}

	.action-btn {
		background-color: #dc3545;
		color: white;
		border-color: #dc3545;
	}

	.action-btn:hover { background-color: #c82333; }

	.zoom-info {
		padding: 6px 8px;
		background-color: #f8f9fa;
		border: 1px solid #ddd;
		border-radius: 4px;
		font-size: 11px;
		text-align: center;
		color: #666;
		margin-top: 6px;
	}

	.instructions {
		font-size: 10px;
		color: #999;
		margin-top: 10px;
		padding: 8px;
		background-color: #f8f9fa;
		border-radius: 4px;
		line-height: 1.5;
	}

	.grid-hint {
		font-size: 10px;
		color: #aaa;
		margin-left: 2px;
	}

	.checkbox-label, .radio-label {
		display: flex;
		align-items: center;
		margin-bottom: 6px;
		font-size: 12px;
		cursor: pointer;
	}

	.checkbox-label input, .radio-label input {
		margin-right: 6px;
		cursor: pointer;
	}

	.range-label {
		display: block;
		font-size: 11px;
		margin-bottom: 6px;
		color: #555;
	}

	.range-label input[type="range"] {
		width: 100%;
		margin-top: 3px;
	}

	.grid-controls {
		margin-top: 6px;
		padding-left: 8px;
		border-left: 2px solid #ddd;
	}

	.grid-controls.disabled {
		opacity: 0.5;
		pointer-events: none;
	}

	/* Auth & Structures */
	.auth-notice {
		font-size: 12px;
		color: #666;
		margin: 4px 0;
	}
	.auth-notice a { color: #0066cc; }

	.save-row {
		display: flex;
		gap: 4px;
		margin-bottom: 6px;
	}

	.name-input {
		flex: 1;
		padding: 6px 8px;
		border: 1px solid #ccc;
		border-radius: 4px;
		font-size: 12px;
		min-width: 0;
	}

	.save-btn {
		padding: 6px 10px;
		background: #28a745;
		color: white;
		border: none;
		border-radius: 4px;
		cursor: pointer;
		font-size: 12px;
		font-weight: bold;
		white-space: nowrap;
	}

	.save-btn:hover { background: #218838; }

	.save-error {
		color: #dc3545;
		font-size: 11px;
		margin: 0 0 6px;
	}

	.structures-list {
		margin-top: 8px;
		max-height: 280px;
		overflow-y: auto;
		border: 1px solid #eee;
		border-radius: 4px;
		background: #fafafa;
	}

	.loading, .empty {
		padding: 12px;
		text-align: center;
		color: #999;
		font-size: 12px;
	}

	.structure-card {
		padding: 8px 10px;
		border-bottom: 1px solid #eee;
		background: white;
	}

	.structure-card:last-child { border-bottom: none; }

	.structure-name {
		font-size: 13px;
		font-weight: bold;
		color: #333;
		margin-bottom: 2px;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.structure-date {
		font-size: 10px;
		color: #aaa;
		margin-bottom: 5px;
	}

	.structure-actions {
		display: flex;
		gap: 4px;
	}

	.card-btn {
		padding: 3px 8px;
		border: 1px solid #ccc;
		border-radius: 3px;
		cursor: pointer;
		font-size: 11px;
		background: white;
	}

	.load-btn { color: #0066cc; border-color: #0066cc; }
	.load-btn:hover { background: #e8f0fb; }
	.copy-btn { color: #555; }
	.copy-btn:hover { background: #f0f0f0; }
	.del-btn { color: #dc3545; border-color: #dc3545; margin-left: auto; }
	.del-btn:hover { background: #fdf0f0; }

	/* Context Menu */
	.context-menu {
		position: fixed;
		background: white;
		border: 1px solid #ccc;
		border-radius: 4px;
		box-shadow: 0 2px 10px rgba(0, 0, 0, 0.12);
		z-index: 1000;
		min-width: 150px;
		padding: 4px 0;
	}

	.context-item {
		padding: 7px 14px;
		cursor: pointer;
		font-size: 13px;
		color: #333;
	}

	.context-item:hover { background-color: #f5f5f5; }
	.context-item.disabled { color: #bbb; cursor: not-allowed; }
	.context-item.disabled:hover { background-color: transparent; }

	.context-divider {
		border: none;
		border-top: 1px solid #eee;
		margin: 3px 0;
	}

	/* Modal */
	.modal-overlay {
		position: fixed;
		top: 0; left: 0; width: 100%; height: 100%;
		background: rgba(0, 0, 0, 0.5);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 2000;
	}

	.modal-content {
		background: white;
		border-radius: 8px;
		max-width: 760px;
		width: 90%;
		max-height: 80vh;
		overflow-y: auto;
		box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
	}

	.modal-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 16px 24px;
		border-bottom: 1px solid #eee;
		background: #f8f9fa;
		border-radius: 8px 8px 0 0;
	}

	.modal-header h2 {
		margin: 0;
		color: #333;
		font-size: 20px;
	}

	.close-btn {
		background: none;
		border: none;
		font-size: 26px;
		cursor: pointer;
		color: #666;
		width: 32px;
		height: 32px;
		border-radius: 50%;
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.close-btn:hover { background: #f0f0f0; color: #333; }

	.modal-body { padding: 24px; }

	.info-section { margin-bottom: 24px; }

	.info-section h3 {
		color: #0066cc;
		margin: 0 0 12px 0;
		font-size: 16px;
		border-bottom: 2px solid #e3f2fd;
		padding-bottom: 6px;
	}

	.structure-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
		gap: 10px;
	}

	.structure-item {
		padding: 12px;
		background: #f3e5f5;
		border-radius: 6px;
		border-left: 4px solid #9c27b0;
		font-size: 13px;
	}

	.structure-item strong { color: #7b1fa2; }

	.trend-grid { display: grid; gap: 10px; }

	.trend-item {
		padding: 12px;
		background: #f8f9fa;
		border-radius: 6px;
		border-left: 4px solid #0066cc;
		font-size: 13px;
	}

	.trend-item em { color: #666; font-size: 12px; }

	.mechanism-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 16px;
	}

	.mechanism-item {
		padding: 16px;
		border-radius: 8px;
		border: 2px solid;
	}

	.mechanism-item.sn1 { background: #fce4ec; border-color: #e91e63; }
	.mechanism-item.sn2 { background: #e8f5e8; border-color: #4caf50; }

	.mechanism-item h4 { margin: 0 0 10px 0; font-size: 15px; }
	.mechanism-item.sn1 h4 { color: #c2185b; }
	.mechanism-item.sn2 h4 { color: #388e3c; }
	.mechanism-item p { margin: 6px 0; font-size: 13px; }
</style>
