<script>
	import { onMount } from 'svelte';
	
	let atoms = [];
	let bonds = [];
	let arrows = [];
	let lonePairs = [];
	
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
	
	// Context menu state
	let contextMenu = { visible: false, x: 0, y: 0 };
	
	// Undo/Redo state management (double stack)
	let undoStack = [];
	let redoStack = [];
	const MAX_UNDO_HISTORY = 50;
	let isBoxSelecting = false;
	let boxStart = { x: 0, y: 0 };
	let boxEnd = { x: 0, y: 0 };
	
	// Pan and zoom state
	let zoom = 1;
	let pan = { x: 0, y: 0 };
	let isPanning = false;
	let lastPanPoint = { x: 0, y: 0 };
	let viewBox = { x: 0, y: 0, width: 800, height: 600 };
	
	// Drag state
	let isDragging = false;
	let draggedAtomId = null;
	let dragOffset = { x: 0, y: 0 };
	
	// Grid system
	let gridEnabled = true;
	let gridType = 'square'; // 'square' or 'hexagonal'
	let gridSize = 40; // Distance between grid points
	let snapToGrid = true;
	
	// Debug cursor
	let debugCursor = { x: 0, y: 0, visible: false };
	
	
	const elements = ['C', 'O', 'N', 'S', 'P', 'H', 'F', 'Cl', 'Br', 'I'];
	const bondTypes = ['single', 'double', 'triple'];
	
	// Reactive statement to regenerate grid when type or size changes
	$: gridPoints = generateGridPoints(gridType, gridSize, viewBox);
	
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
		
		// Calculate the aal viewBox aspect ratio vs rendered aspect ratio
		const viewBoxAspect = viewBox.width / viewBox.height;
		const renderedAspect = rect.width / rect.height;
		
		let actualSVGWidth, actualSVGHeight, offsetX, offsetY;
		
		if (viewBoxAspect > renderedAspect) {
			// ViewBox is widtainer - letterboxed vertically
			actualSVGWidth = rect.width;
			actualSVGHeight = rect.width / viewBoxAspect;
			offsetX = 0;
			offsetY = (rect.height - actualSVGHeight) / 2;
		} else {
			// ViewBox is taller than container - letterboxed horizontally
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
			// Hexagonal grid with proper equidistant spacing for 120° angles
			const hexHeight = gridSize * Math.sqrt(3) / 2; // Vertical spacing between rows
			const hexWidth = gridSize; // Horizontal spacing between columns
			
			// Calculate which row and column this point is closest to
			const row = Math.round(y / hexHeight);
			const col = Math.round((x - (row % 2) * (hexWidth / 2)) / hexWidth);
			
			// Calculate the actual grid position
			const gridX = col * hexWidth + (row % 2) * (hexWidth / 2);
			const gridY = row * hexHeight;
			
			return {
				x: gridX,
				y: gridY
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
			// Square grid
			const firstX = Math.floor(startX / gridSize) * gridSize;
			const firstY = Math.floor(startY / gridSize) * gridSize;
			
			for (let x = firstX; x <= endX; x += gridSize) {
				for (let y = firstY; y <= endY; y += gridSize) {
					points.push({ x, y });
				}
			}
		} else if (gridType === 'hexagonal') {
			// Hexagonal grid with proper equidistant spacing for perfect 120° angles
			const hexHeight = gridSize * Math.sqrt(3) / 2; // Correct vertical spacing
			const hexWidth = gridSize; // Horizontal spacing between columns
			
			const firstRow = Math.floor(startY / hexHeight);
			const lastRow = Math.ceil(endY / hexHeight);
			const firstCol = Math.floor(startX / hexWidth);
			const lastCol = Math.ceil(endX / hexWidth);
			
			for (let row = firstRow; row <= lastRow; row++) {
				for (let col = firstCol; col <= lastCol; col++) {
					// Offset every other row by half the horizontal spacing
					const offsetX = (row % 2) * (hexWidth / 2);
					const x = col * hexWidth + offsetX;
					const y = row * hexHeight;
					
					if (x >= startX && x <= endX && y >= startY && y <= endY) {
						points.push({ x, y });
					}
				}
			}
		}
		
		return points;
	}
	
	function handleSVGMouseMove(event) {
		if (!isPanning) {
			const coords = getCanvasCoordinates(event);
			debugCursor = { x: coords.x, y: coords.y, visible: true };
			
			// Update temp arrow if drawing
			if (tempArrow && selectedTool === 'arrow') {
				updateArrow(coords.x, coords.y);
			}
		}
	}
	
	function handleSVGMouseLeave() {
		debugCursor.visible = false;
	}
	
	let justFinishedBoxSelect = false;
	
	function handleSVGClick(event) {
		// Don't handle click if we just finished a box selection
		if (isPanning || justFinishedBoxSelect) {
			justFinishedBoxSelect = false;
			return;
		}
		
		const coords = getCanvasCoordinates(event);
		console.log('SVG clicked, tool:', selectedTool, 'coords:', coords);
		
		if (selectedTool === 'atom') {
			addAtom(coords.x, coords.y);
		} else if (selectedTool === 'arrow') {
			if (tempArrow) {
				completeArrow();
			} else {
				startArrow(coords.x, coords.y);
			}
		} else if (selectedTool === 'select') {
			// Clear selection if clicking on empty space and not holding shift
			if (!event.shiftKey) {
				console.log('Clearing selection (clicked empty space)');
				selectedAtoms.clear();
				selectedArrows.clear();
				selectedBonds.clear();
				selectedAtoms = new Set(selectedAtoms);
				selectedArrows = new Set(selectedArrows);
				selectedBonds = new Set(selectedBonds);
				// Update atom objects for visual feedback
				atoms = atoms.map(atom => ({
					...atom,
					selected: false
				}));
			}
		}
	}
	
	function addAtom(x, y) {
		saveState(); // Save state before making changes
		
		const newAtom = {
			id: generateId(),
			x,
			y,
			element: selectedElement,
			selected: false
		};
		atoms = [...atoms, newAtom];
		
		// Update graph representation
		moleculeGraph.nodes.set(newAtom.id, newAtom);
		moleculeGraph.adjacency.set(newAtom.id, new Set());
	}
	
	function selectAtom(atomId, addToSelection = false) {
		console.log('Selecting atom:', atomId, 'addToSelection:', addToSelection);
		if (addToSelection) {
			// Toggle selection for this atom
			if (selectedAtoms.has(atomId)) {
				selectedAtoms.delete(atomId);
			} else {
				selectedAtoms.add(atomId);
			}
		} else {
			// Single selection - clear others and select this one
			selectedAtoms.clear();
			selectedAtoms.add(atomId);
		}
		selectedAtoms = new Set(selectedAtoms); // Trigger reactivity
		console.log('Selected atoms after:', Array.from(selectedAtoms));
		
		// Update atom objects for visual feedback
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
			saveState(); // Save state before making changes
			
			const newBond = {
				id: generateId(),
				atomId1: tempBond.startAtomId,
				atomId2: endAtomId,
				type: 'single'
			};
			bonds = [...bonds, newBond];
			
			// Update graph representation
			moleculeGraph.edges.set(newBond.id, newBond);
			if (!moleculeGraph.adjacency.has(newBond.atomId1)) {
				moleculeGraph.adjacency.set(newBond.atomId1, new Set());
			}
			if (!moleculeGraph.adjacency.has(newBond.atomId2)) {
				moleculeGraph.adjacency.set(newBond.atomId2, new Set());
			}
			moleculeGraph.adjacency.get(newBond.atomId1).add(newBond.atomId2);
			moleculeGraph.adjacency.get(newBond.atomId2).add(newBond.atomId1);
		}
		tempBond = null;
	}
	
	function startArrow(x, y) {
		if (!tempArrow) {
			tempArrow = { startX: x, startY: y, endX: x, endY: y };
			console.log('Started arrow at:', x, y);
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
			saveState(); // Save state before making changes
			
			const newArrow = {
				id: generateId(),
				startX: tempArrow.startX,
				startY: tempArrow.startY,
				endX: tempArrow.endX,
				endY: tempArrow.endY,
				type: 'reaction'
			};
			arrows = [...arrows, newArrow];
			console.log('Completed arrow:', newArrow);
			tempArrow = null;
		}
	}
	
	function addLonePair(atomId, angle) {
		saveState(); // Save state before making changes
		
		const newLonePair = {
			id: generateId(),
			atomId: atomId,
			angle: angle // angle in radians for positioning around atom
		};
		lonePairs = [...lonePairs, newLonePair];
		console.log('Added lone pair to atom:', atomId, 'at angle:', angle);
	}
	
	function getLonePairPosition(atomId, angle) {
		const atom = atoms.find(a => a.id === atomId);
		if (!atom) return { x: 0, y: 0 };
		
		const distance = 25; // Distance from atom center
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
			selectedAtoms: new Set(selectedAtoms),
			selectedArrows: new Set(selectedArrows),
			selectedBonds: new Set(selectedBonds)
		};
		
		undoStack.push(state);
		if (undoStack.length > MAX_UNDO_HISTORY) {
			undoStack.shift(); // Remove oldest state
		}
		
		// Clear redo stack when new action is performed
		redoStack = [];
		
		console.log('State saved, undo stack size:', undoStack.length);
	}
	
	function restoreState(state) {
		atoms = JSON.parse(JSON.stringify(state.atoms));
		bonds = JSON.parse(JSON.stringify(state.bonds));
		arrows = JSON.parse(JSON.stringify(state.arrows));
		lonePairs = JSON.parse(JSON.stringify(state.lonePairs));
		selectedAtoms = new Set(state.selectedAtoms);
		selectedArrows = new Set(state.selectedArrows);
		selectedBonds = new Set(state.selectedBonds);
		
		// Rebuild graph representation
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
			// Save current state to redo stack
			const currentState = {
				atoms: JSON.parse(JSON.stringify(atoms)),
				bonds: JSON.parse(JSON.stringify(bonds)),
				arrows: JSON.parse(JSON.stringify(arrows)),
				lonePairs: JSON.parse(JSON.stringify(lonePairs)),
				selectedAtoms: new Set(selectedAtoms),
				selectedArrows: new Set(selectedArrows),
				selectedBonds: new Set(selectedBonds)
			};
			redoStack.push(currentState);
			
			// Restore previous state
			const previousState = undoStack.pop();
			restoreState(previousState);
			
			console.log('Undo performed, undo stack:', undoStack.length, 'redo stack:', redoStack.length);
		}
	}
	
	function redo() {
		if (redoStack.length > 0) {
			// Save current state to undo stack
			saveState();
			undoStack.pop(); // Remove the duplicate we just added
			
			// Restore next state
			const nextState = redoStack.pop();
			restoreState(nextState);
			
			console.log('Redo performed, undo stack:', undoStack.length, 'redo stack:', redoStack.length);
		}
	}
	
	function startAtomDrag(atomId, event) {
		if (selectedTool === 'select' && selectedAtoms.has(atomId)) {
			event.stopPropagation();
			saveState(); // Save state before dragging starts
			
			isDragging = true;
			draggedAtomId = atomId;
			
			const atom = atoms.find(a => a.id === atomId);
			const coords = getCanvasCoordinates(event);
			dragOffset = {
				x: coords.x - atom.x,
				y: coords.y - atom.y
			};
			console.log('Started dragging atom:', atomId);
		}
	}
	
	function updateAtomPosition(atomId, newX, newY) {
		// Update atom position
		atoms = atoms.map(atom => 
			atom.id === atomId ? { ...atom, x: newX, y: newY } : atom
		);
		
		// Update graph representation
		const atom = moleculeGraph.nodes.get(atomId);
		if (atom) {
			moleculeGraph.nodes.set(atomId, { ...atom, x: newX, y: newY });
		}
		
		// Force bonds to re-render by triggering reactivity
		bonds = [...bonds];
	}
	
	function isBondInBox(bond, minX, maxX, minY, maxY) {
		const atom1 = atoms.find(a => a.id === bond.atomId1);
		const atom2 = atoms.find(a => a.id === bond.atomId2);
		
		if (!atom1 || !atom2) return false;
		
		const startInBox = atom1.x >= minX && atom1.x <= maxX && 
		                   atom1.y >= minY && atom1.y <= maxY;
		const endInBox = atom2.x >= minX && atom2.x <= maxX && 
		                 atom2.y >= minY && atom2.y <= maxY;
		
		// Bond is selected if either endpoint is in the box
		return startInBox || endInBox;
	}
	
	function isArrowInBox(arrow, minX, maxX, minY, maxY) {
		// Check if arrow line intersects with or is contained in the selection box
		const startInBox = arrow.startX >= minX && arrow.startX <= maxX && 
		                   arrow.startY >= minY && arrow.startY <= maxY;
		const endInBox = arrow.endX >= minX && arrow.endX <= maxX && 
		                 arrow.endY >= minY && arrow.endY <= maxY;
		
		// Arrow is selected if either endpoint is in the box, or if line crosses the box
		return startInBox || endInBox;
	}
	
	function getAtomColor(element) {
		const colors = {
			'C': '#000000',
			'O': '#ff0000',
			'N': '#0000ff',
			'S': '#ffff00',
			'P': '#ff8000',
			'H': '#ffffff',
			'F': '#90e050',
			'Cl': '#1ff01f',
			'Br': '#a62929',
			'I': '#940094'
		};
		return colors[element] || '#000000';
	}
	
	function getBondPaths(bond) {
		const atom1 = atoms.find(a => a.id === bond.atomId1);
		const atom2 = atoms.find(a => a.id === bond.atomId2);
		
		if (!atom1 || !atom2) return [];
		
		const dx = atom2.x - atom1.x;
		const dy = atom2.y - atom1.y;
		const length = Math.sqrt(dx * dx + dy * dy);
		const unitX = dx / length;
		const unitY = dy / length;
		
		// Perpendicular vector for parallel bonds
		const perpX = -unitY * 3;
		const perpY = unitX * 3;
		
		if (bond.type === 'single') {
			return [`M ${atom1.x} ${atom1.y} L ${atom2.x} ${atom2.y}`];
		} else if (bond.type === 'double') {
			return [
				`M ${atom1.x + perpX} ${atom1.y + perpY} L ${atom2.x + perpX} ${atom2.y + perpY}`,
				`M ${atom1.x - perpX} ${atom1.y - perpY} L ${atom2.x - perpX} ${atom2.y - perpY}`
			];
		} else if (bond.type === 'triple') {
			return [
				`M ${atom1.x} ${atom1.y} L ${atom2.x} ${atom2.y}`,
				`M ${atom1.x + perpX} ${atom1.y + perpY} L ${atom2.x + perpX} ${atom2.y + perpY}`,
				`M ${atom1.x - perpX} ${atom1.y - perpY} L ${atom2.x - perpX} ${atom2.y - perpY}`
			];
		}
		
		return [];
	}
	
	function deleteSelected() {
		console.log('Delete called, selected atoms:', selectedAtoms.size, 'bonds:', selectedBonds.size, 'arrows:', selectedArrows.size);
		if (selectedAtoms.size > 0 || selectedArrows.size > 0 || selectedBonds.size > 0) {
			saveState(); // Save state before making changes
			
			const atomIdsToDelete = Array.from(selectedAtoms);
			
			// Remove atoms
			atoms = atoms.filter(atom => !selectedAtoms.has(atom.id));
			
			// Remove bonds connected to deleted atoms
			const bondsToDelete = bonds.filter(bond => 
				selectedAtoms.has(bond.atomId1) || selectedAtoms.has(bond.atomId2)
			);
			bonds = bonds.filter(bond => 
				!selectedAtoms.has(bond.atomId1) && !selectedAtoms.has(bond.atomId2)
			);
			
			// Remove lone pairs connected to deleted atoms
			lonePairs = lonePairs.filter(lp => !selectedAtoms.has(lp.atomId));
			
			// Remove selected arrows
			arrows = arrows.filter(arrow => !selectedArrows.has(arrow.id));
			
			// Remove selected bonds (independent of atom deletion)
			const selectedBondsToDelete = bonds.filter(bond => selectedBonds.has(bond.id));
			bonds = bonds.filter(bond => !selectedBonds.has(bond.id));
			
			// Update graph representation for deleted bonds
			selectedBondsToDelete.forEach(bond => {
				moleculeGraph.edges.delete(bond.id);
				if (moleculeGraph.adjacency.has(bond.atomId1)) {
					moleculeGraph.adjacency.get(bond.atomId1).delete(bond.atomId2);
				}
				if (moleculeGraph.adjacency.has(bond.atomId2)) {
					moleculeGraph.adjacency.get(bond.atomId2).delete(bond.atomId1);
				}
			});
			
			// Update graph representation
			atomIdsToDelete.forEach(atomId => {
				moleculeGraph.nodes.delete(atomId);
				moleculeGraph.adjacency.delete(atomId);
			});
			
			bondsToDelete.forEach(bond => {
				moleculeGraph.edges.delete(bond.id);
				// Remove from adjacency lists
				if (moleculeGraph.adjacency.has(bond.atomId1)) {
					moleculeGraph.adjacency.get(bond.atomId1).delete(bond.atomId2);
				}
				if (moleculeGraph.adjacency.has(bond.atomId2)) {
					moleculeGraph.adjacency.get(bond.atomId2).delete(bond.atomId1);
				}
			});
			
			selectedAtoms.clear();
			selectedArrows.clear();
			selectedBonds.clear();
			selectedAtoms = new Set(selectedAtoms);
			selectedArrows = new Set(selectedArrows);
			selectedBonds = new Set(selectedBonds);
		}
	}
	
	function selectAll() {
		// Select all atoms, bonds, and arrows
		selectedAtoms.clear();
		selectedArrows.clear();
		selectedBonds.clear();
		
		atoms.forEach(atom => selectedAtoms.add(atom.id));
		arrows.forEach(arrow => selectedArrows.add(arrow.id));
		bonds.forEach(bond => selectedBonds.add(bond.id));
		
		selectedAtoms = new Set(selectedAtoms);
		selectedArrows = new Set(selectedArrows);
		selectedBonds = new Set(selectedBonds);
		
		// Update atom visual feedback
		atoms = atoms.map(atom => ({
			...atom,
			selected: true
		}));
		
		console.log('Selected all - atoms:', selectedAtoms.size, 'bonds:', selectedBonds.size, 'arrows:', selectedArrows.size);
	}
	
	function handleKeyDown(event) {
		if (event.key === 'Delete' || event.key === 'Backspace') {
			deleteSelected();
		} else if ((event.metaKey || event.ctrlKey) && event.key === 'a') {
			event.preventDefault();
			selectAll();
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
		event.preventDefault(); // Disable browser context menu
		
		// Get screen coordinates for context menu positioning
		contextMenu = {
			visible: true,
			x: event.clientX,
			y: event.clientY
		};
	}
	
	function hideContextMenu() {
		contextMenu.visible = false;
	}
	
	// Pan and zoom handlers
	function handleMouseDown(event) {
		if (event.button === 1 || (event.button === 0 && event.altKey)) {
			// Middle mouse or Alt+left mouse for panning
			event.preventDefault();
			isPanning = true;
			lastPanPoint = { x: event.clientX, y: event.clientY };
			svgElement.style.cursor = 'grabbing';
		} else if (event.button === 0 && selectedTool === 'select') {
			// Start box selection
			event.preventDefault();
			const coords = getCanvasCoordinates(event);
			isBoxSelecting = true;
			boxStart = { x: coords.x, y: coords.y };
			boxEnd = { x: coords.x, y: coords.y };
			console.log('Starting box selection at:', coords);
		}
	}
	
	function handleMouseMove(event) {
		if (isPanning) {
			event.preventDefault();
			const dx = event.clientX - lastPanPoint.x;
			const dy = event.clientY - lastPanPoint.y;
			
			pan.x += dx / zoom;
			pan.y += dy / zoom;
			pan = { ...pan }; // Trigger reactivity
			
			lastPanPoint = { x: event.clientX, y: event.clientY };
			updateViewBox();
		} else if (isDragging && draggedAtomId) {
			// Update atom position while dragging
			event.preventDefault();
			const coords = getCanvasCoordinates(event);
			let newX = coords.x - dragOffset.x;
			let newY = coords.y - dragOffset.y;
			
			// Snap to grid if enabled
			if (snapToGrid && gridEnabled) {
				const snapped = snapToGridPoint(newX, newY);
				newX = snapped.x;
				newY = snapped.y;
			}
			
			updateAtomPosition(draggedAtomId, newX, newY);
		} else if (isBoxSelecting) {
			// Update box selection
			event.preventDefault();
			const coords = getCanvasCoordinates(event);
			boxEnd = { x: coords.x, y: coords.y };
		}
	}
	
	function handleMouseUp(event) {
		if (isPanning) {
			isPanning = false;
			svgElement.style.cursor = 'default';
		} else if (isDragging) {
			isDragging = false;
			draggedAtomId = null;
			console.log('Stopped dragging atom');
		} else if (isBoxSelecting) {
			// Complete box selection
			isBoxSelecting = false;
			justFinishedBoxSelect = true;
			
			// Find atoms within selection box
			const minX = Math.min(boxStart.x, boxEnd.x);
			const maxX = Math.max(boxStart.x, boxEnd.x);
			const minY = Math.min(boxStart.y, boxEnd.y);
			const maxY = Math.max(boxStart.y, boxEnd.y);
			
			const selectedInBox = atoms.filter(atom => 
				atom.x >= minX && atom.x <= maxX && 
				atom.y >= minY && atom.y <= maxY
			);
			
			const arrowsInBox = arrows.filter(arrow => 
				isArrowInBox(arrow, minX, maxX, minY, maxY)
			);
			
			const bondsInBox = bonds.filter(bond => 
				isBondInBox(bond, minX, maxX, minY, maxY)
			);
			
			console.log('Box selection complete. Found atoms:', selectedInBox.length, 'arrows:', arrowsInBox.length, 'bonds:', bondsInBox.length);
			
			// Add to selection (or replace if not holding shift)
			if (!event.shiftKey) {
				selectedAtoms.clear();
				selectedArrows.clear();
				selectedBonds.clear();
			}
			
			selectedInBox.forEach(atom => selectedAtoms.add(atom.id));
			arrowsInBox.forEach(arrow => selectedArrows.add(arrow.id));
			bondsInBox.forEach(bond => selectedBonds.add(bond.id));
			selectedAtoms = new Set(selectedAtoms); // Trigger reactivity
			selectedArrows = new Set(selectedArrows); // Trigger reactivity
			selectedBonds = new Set(selectedBonds); // Trigger reactivity
			
			console.log('Total selected - atoms:', Array.from(selectedAtoms), 'arrows:', Array.from(selectedArrows), 'bonds:', Array.from(selectedBonds));
			
			// Update atom objects for visual feedback
			atoms = atoms.map(atom => ({
				...atom,
				selected: selectedAtoms.has(atom.id)
			}));
		}
	}
	
	function handleWheel(event) {
		event.preventDefault();
		
		if (event.ctrlKey || event.metaKey) {
			// Zoom with Ctrl/Cmd + scroll
			const rect = svgElement.getBoundingClientRect();
			const mouseX = event.clientX - rect.left;
			const mouseY = event.clientY - rect.top;
			
			const zoomFactor = event.deltaY > 0 ? 0.9 : 1.1;
			const newZoom = Math.max(0.1, Math.min(zoom * zoomFactor, 5));
			
			// Calculate world coordinates of mouse position before zoom
			const worldX = (mouseX / zoom) - pan.x;
			const worldY = (mouseY / zoom) - pan.y;
			
			// Update zoom
			zoom = newZoom;
			
			// Calculate new pan to keep the same world point under the mouse
			pan.x = (mouseX / zoom) - worldX;
			pan.y = (mouseY / zoom) - worldY;
			pan = { ...pan }; // Trigger reactivity
			updateViewBox();
		} else {
			// Pan with trackpad scroll (inverted for natural feeling)
			pan.x -= event.deltaX / zoom;
			pan.y -= event.deltaY / zoom;
			pan = { ...pan }; // Trigger reactivity
			updateViewBox();
		}
	}
	
	// Touch handlers for pinch zoom and pan
	let touches = [];
	let initialDistance = 0;
	let initialZoom = 1;
	let initialPan = { x: 0, y: 0 };
	
	function handleTouchStart(event) {
		touches = Array.from(event.touches);
		
		if (touches.length === 2) {
			// Two finger pinch/zoom
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
			// Single finger pan
			lastPanPoint = { x: touches[0].clientX, y: touches[0].clientY };
		}
	}
	
	function handleTouchMove(event) {
		event.preventDefault();
		touches = Array.from(event.touches);
		
		if (touches.length === 2) {
			// Two finger pinch/zoom
			const touch1 = touches[0];
			const touch2 = touches[1];
			
			const currentDistance = Math.sqrt(
				Math.pow(touch2.clientX - touch1.clientX, 2) +
				Math.pow(touch2.clientY - touch1.clientY, 2)
			);
			
			const zoomFactor = currentDistance / initialDistance;
			zoom = Math.max(0.1, Math.min(initialZoom * zoomFactor, 5));
			
			// Center point of pinch
			const centerX = (touch1.clientX + touch2.clientX) / 2;
			const centerY = (touch1.clientY + touch2.clientY) / 2;
			
			const rect = svgElement.getBoundingClientRect();
			const relativeCenterX = centerX - rect.left;
			const relativeCenterY = centerY - rect.top;
			
			// Zoom towards pinch center
			pan.x = relativeCenterX - (relativeCenterX - initialPan.x) * (zoom / initialZoom);
			pan.y = relativeCenterY - (relativeCenterY - initialPan.y) * (zoom / initialZoom);
			pan = { ...pan }; // Trigger reactivity
			
			updateViewBox();
		} else if (touches.length === 1) {
			// Single finger pan
			const dx = touches[0].clientX - lastPanPoint.x;
			const dy = touches[0].clientY - lastPanPoint.y;
			
			pan.x += dx / zoom;
			pan.y += dy / zoom;
			pan = { ...pan }; // Trigger reactivity
			
			lastPanPoint = { x: touches[0].clientX, y: touches[0].clientY };
			updateViewBox();
		}
	}
	
	function handleTouchEnd(event) {
		touches = Array.from(event.touches);
	}
	
	onMount(() => {
		document.addEventListener('keydown', handleKeyDown);
		document.addEventListener('click', hideContextMenu);
		return () => {
			document.removeEventListener('keydown', handleKeyDown);
			document.removeEventListener('click', hideContextMenu);
		};
	});
</script>

<svelte:head>
	<title>Chemical Drawing App</title>
</svelte:head>

<div class="app">
	<div class="toolbar">
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
				Add Atom
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
				class="tool-btn {selectedTool === 'lonepair' ? 'active' : ''}"
				on:click={() => selectedTool = 'lonepair'}
			>
				Lone Pair
			</button>
		</div>
		
		<div class="tool-group">
			<h3>Elements</h3>
			<div class="element-grid">
				{#each elements as element}
					<button 
						class="element-btn {selectedElement === element ? 'active' : ''}"
						style="background-color: {getAtomColor(element)}; color: {element === 'H' || element === 'S' ? '#000' : '#fff'}"
						on:click={() => selectedElement = element}
					>
						{element}
					</button>
				{/each}
			</div>
		</div>
		
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
					Square Grid
				</label>
				<label class="radio-label">
					<input 
						type="radio" 
						bind:group={gridType} 
						value="hexagonal"
						disabled={!gridEnabled}
					/>
					Hexagonal Grid
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
			<div class="zoom-info">
				Zoom: {Math.round(zoom * 100)}%
			</div>
		</div>
		
		<div class="tool-group">
			<h3>Actions</h3>
			<button class="tool-btn" on:click={undo} disabled={undoStack.length === 0}>
				Undo (⌘Z)
			</button>
			<button class="tool-btn" on:click={redo} disabled={redoStack.length === 0}>
				Redo (⌘⇧Z)
			</button>
			<button class="action-btn" on:click={deleteSelected}>
				Delete Selected
			</button>
			<button class="action-btn" on:click={() => { saveState(); atoms = []; bonds = []; arrows = []; lonePairs = []; selectedAtoms.clear(); selectedArrows.clear(); selectedBonds.clear(); selectedAtoms = new Set(); selectedArrows = new Set(); selectedBonds = new Set(); }}>
				Clear All
			</button>
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
			{/if}
			
			<!-- Bonds -->
			{#each bonds as bond}
				{#each getBondPaths(bond) as path}
					<path 
						d={path}
						stroke={selectedBonds.has(bond.id) ? "#0066cc" : "#000000"}
						stroke-width={selectedBonds.has(bond.id) ? "3" : "2"}
						fill="none"
						on:click={(e) => {
							if (selectedTool === 'bond') {
								saveState(); // Save state before changing bond type
								const currentTypeIndex = bondTypes.indexOf(bond.type);
								const nextTypeIndex = (currentTypeIndex + 1) % bondTypes.length;
								bonds = bonds.map(b => 
									b.id === bond.id ? { ...b, type: bondTypes[nextTypeIndex] } : b
								);
							} else if (selectedTool === 'select') {
								e.stopPropagation();
								if (e.shiftKey) {
									// Toggle bond selection
									if (selectedBonds.has(bond.id)) {
										selectedBonds.delete(bond.id);
									} else {
										selectedBonds.add(bond.id);
									}
								} else {
									// Single selection
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
					d="M {tempBond.x} {tempBond.y} L {tempBond.x} {tempBond.y}"
					stroke="#999999"
					stroke-width="2"
					stroke-dasharray="5,5"
					fill="none"
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
						<polygon 
							points="0 0, 10 3.5, 0 7" 
							fill="#000000" 
						/>
					</marker>
				</defs>
				<line 
					x1={arrow.startX} 
					y1={arrow.startY} 
					x2={arrow.endX} 
					y2={arrow.endY}
					stroke={selectedArrows.has(arrow.id) ? "#0066cc" : "#000000"}
					stroke-width={selectedArrows.has(arrow.id) ? "4" : "3"}
					marker-end="url(#arrowhead-{arrow.id})"
					style="cursor: pointer;"
					on:click={(e) => {
						if (selectedTool === 'select') {
							e.stopPropagation();
							if (e.shiftKey) {
								// Toggle arrow selection
								if (selectedArrows.has(arrow.id)) {
									selectedArrows.delete(arrow.id);
								} else {
									selectedArrows.add(arrow.id);
								}
							} else {
								// Single selection
								selectedArrows.clear();
								selectedArrows.add(arrow.id);
							}
							selectedArrows = new Set(selectedArrows);
						}
					}}
				/>
			{/each}
			
			<!-- Temporary arrow while drawing -->
			{#if tempArrow}
				<defs>
					<marker 
						id="temp-arrowhead" 
						markerWidth="10" 
						markerHeight="7" 
						refX="9" 
						refY="3.5" 
						orient="auto"
					>
						<polygon 
							points="0 0, 10 3.5, 0 7" 
							fill="#999999" 
						/>
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
					<circle 
						cx={atom.x} 
						cy={atom.y} 
						r="15"
						fill={getAtomColor(atom.element)}
						stroke={atom.selected ? "#0066cc" : "#000000"}
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
								// Add lone pair at a smart angle
								const existingPairs = lonePairs.filter(lp => lp.atomId === atom.id);
								const angle = existingPairs.length * (Math.PI / 2); // 90° increments
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
						font-size="14" 
						font-weight="bold"
						fill={atom.element === 'H' || atom.element === 'S' ? '#000' : '#fff'}
						pointer-events="none"
					>
						{atom.element}
					</text>
				</g>
			{/each}
			
			<!-- Lone Pairs -->
			{#each lonePairs as lonePair}
				{@const position = getLonePairPosition(lonePair.atomId, lonePair.angle)}
				<g>
					<!-- Two dots for lone pair -->
					<circle 
						cx={position.x - 3} 
						cy={position.y} 
						r="2"
						fill="#000000"
					/>
					<circle 
						cx={position.x + 3} 
						cy={position.y} 
						r="2"
						fill="#000000"
					/>
				</g>
			{/each}
			
			<!-- Box selection rectangle -->
			{#if isBoxSelecting}
				<rect 
					x={Math.min(boxStart.x, boxEnd.x)} 
					y={Math.min(boxStart.y, boxEnd.y)} 
					width={Math.abs(boxEnd.x - boxStart.x)} 
					height={Math.abs(boxEnd.y - boxStart.y)}
					fill="rgba(0, 102, 204, 0.2)"
					stroke="#0066cc"
					stroke-width="1"
					stroke-dasharray="5,5"
					pointer-events="none"
				/>
			{/if}
			
			<!-- Debug cursor indicator -->
			{#if debugCursor.visible}
				<circle 
					cx={debugCursor.x} 
					cy={debugCursor.y} 
					r="5"
					fill="red"
					opacity="0.7"
					pointer-events="none"
				/>
				<line 
					x1={debugCursor.x - 10} 
					y1={debugCursor.y} 
					x2={debugCursor.x + 10} 
					y2={debugCursor.y}
					stroke="red"
					stroke-width="1"
					pointer-events="none"
				/>
				<line 
					x1={debugCursor.x} 
					y1={debugCursor.y - 10} 
					x2={debugCursor.x} 
					y2={debugCursor.y + 10}
					stroke="red"
					stroke-width="1"
					pointer-events="none"
				/>
			{/if}
		</svg>
	</div>
</div>

<!-- Custom Context Menu -->
{#if contextMenu.visible}
	<div 
		class="context-menu"
		style="left: {contextMenu.x}px; top: {contextMenu.y}px;"
		on:click|stopPropagation
	>
		<div class="context-item {undoStack.length === 0 ? 'disabled' : ''}" on:click={() => { if (undoStack.length > 0) { undo(); hideContextMenu(); } }}>
			Undo (⌘Z)
		</div>
		<div class="context-item {redoStack.length === 0 ? 'disabled' : ''}" on:click={() => { if (redoStack.length > 0) { redo(); hideContextMenu(); } }}>
			Redo (⌘⇧Z)
		</div>
		<hr class="context-divider">
		<div class="context-item" on:click={() => { selectAll(); hideContextMenu(); }}>
			Select All (⌘A)
		</div>
		<div class="context-item" on:click={() => { deleteSelected(); hideContextMenu(); }}>
			Delete Selected
		</div>
		<hr class="context-divider">
		<div class="context-item" on:click={() => { saveState(); atoms = []; bonds = []; arrows = []; lonePairs = []; selectedAtoms.clear(); selectedArrows.clear(); selectedBonds.clear(); hideContextMenu(); }}>
			Clear All
		</div>
	</div>
{/if}

<style>
	.app {
		display: flex;
		height: 100vh;
		font-family: Arial, sans-serif;
		user-select: none; /* Prevent text selection */
		-webkit-user-select: none;
		-moz-user-select: none;
		-ms-user-select: none;
	}
	
	.toolbar {
		width: 250px;
		background-color: #f5f5f5;
		padding: 20px;
		border-right: 1px solid #ddd;
		overflow-y: auto;
	}
	
	.tool-group {
		margin-bottom: 30px;
	}
	
	.tool-group h3 {
		margin: 0 0 10px 0;
		color: #333;
		font-size: 16px;
	}
	
	.tool-btn, .action-btn {
		display: block;
		width: 100%;
		padding: 10px;
		margin-bottom: 5px;
		border: 1px solid #ccc;
		background-color: #fff;
		cursor: pointer;
		border-radius: 4px;
		font-size: 14px;
	}
	
	.tool-btn:hover, .action-btn:hover {
		background-color: #f0f0f0;
	}
	
	.tool-btn.active {
		background-color: #0066cc;
		color: white;
		border-color: #0066cc;
	}
	
	.element-grid {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 5px;
	}
	
	.element-btn {
		padding: 10px;
		border: 1px solid #ccc;
		cursor: pointer;
		border-radius: 4px;
		font-weight: bold;
		font-size: 14px;
	}
	
	.element-btn:hover {
		opacity: 0.8;
	}
	
	.element-btn.active {
		border-width: 3px;
		border-color: #0066cc;
	}
	
	.drawing-area {
		flex: 1;
		background-color: white;
		overflow: hidden;
	}
	
	svg {
		background-color: white;
		border: 1px solid #eee;
	}
	
	.action-btn {
		background-color: #dc3545;
		color: white;
		border-color: #dc3545;
	}
	
	.action-btn:hover {
		background-color: #c82333;
	}
	
	.zoom-info {
		padding: 8px;
		background-color: #f8f9fa;
		border: 1px solid #ddd;
		border-radius: 4px;
		font-size: 12px;
		text-align: center;
		color: #666;
		margin-top: 10px;
	}
	
	svg {
		touch-action: none; /* Prevent default touch behaviors */
		user-select: none;
	}
	
	.drawing-area svg.panning {
		cursor: grabbing !important;
	}
	
	/* Instructions text */
	.instructions {
		font-size: 11px;
		color: #888;
		margin-top: 15px;
		padding: 10px;
		background-color: #f8f9fa;
		border-radius: 4px;
		line-height: 1.4;
	}
	
	/* Grid controls */
	.checkbox-label, .radio-label {
		display: flex;
		align-items: center;
		margin-bottom: 8px;
		font-size: 14px;
		cursor: pointer;
	}
	
	.checkbox-label input, .radio-label input {
		margin-right: 8px;
		cursor: pointer;
	}
	
	.range-label {
		display: block;
		font-size: 12px;
		margin-bottom: 8px;
		color: #555;
	}
	
	.range-label input[type="range"] {
		width: 100%;
		margin-top: 4px;
	}
	
	.grid-controls {
		margin-top: 10px;
		padding-left: 10px;
		border-left: 2px solid #ddd;
	}
	
	.grid-controls.disabled {
		opacity: 0.5;
		pointer-events: none;
	}
	
	input:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}
	
	/* Context Menu */
	.context-menu {
		position: fixed;
		background: white;
		border: 1px solid #ccc;
		border-radius: 4px;
		box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
		z-index: 1000;
		min-width: 150px;
		padding: 4px 0;
	}
	
	.context-item {
		padding: 8px 16px;
		cursor: pointer;
		font-size: 14px;
		color: #333;
	}
	
	.context-item:hover {
		background-color: #f5f5f5;
	}
	
	.context-item.disabled {
		color: #999;
		cursor: not-allowed;
	}
	
	.context-item.disabled:hover {
		background-color: transparent;
	}
	
	.context-divider {
		border: none;
		border-top: 1px solid #eee;
		margin: 4px 0;
	}
	
	.tool-btn:disabled {
		opacity: 0.5;
		cursor: not-allowed;
		background-color: #f8f9fa;
	}
</style>