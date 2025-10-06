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
	let selectedLonePairs = new Set();
	
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
				selectedLonePairs.clear();
				selectedAtoms = new Set(selectedAtoms);
				selectedArrows = new Set(selectedArrows);
				selectedBonds = new Set(selectedBonds);
				selectedLonePairs = new Set(selectedLonePairs);
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
			selectedBonds: new Set(selectedBonds),
			selectedLonePairs: new Set(selectedLonePairs)
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
		selectedLonePairs = new Set(state.selectedLonePairs);
		
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
				selectedBonds: new Set(selectedBonds),
				selectedLonePairs: new Set(selectedLonePairs)
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
	
	function isLonePairInBox(lonePair, minX, maxX, minY, maxY) {
		const position = getLonePairPosition(lonePair.atomId, lonePair.angle);
		return position.x >= minX && position.x <= maxX && 
		       position.y >= minY && position.y <= maxY;
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
		console.log('Delete called, selected atoms:', selectedAtoms.size, 'bonds:', selectedBonds.size, 'arrows:', selectedArrows.size, 'lone pairs:', selectedLonePairs.size);
		if (selectedAtoms.size > 0 || selectedArrows.size > 0 || selectedBonds.size > 0 || selectedLonePairs.size > 0) {
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
			
			// Remove selected lone pairs (independent of atom deletion)
			lonePairs = lonePairs.filter(lp => !selectedLonePairs.has(lp.id));
			
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
			selectedLonePairs.clear();
			selectedAtoms = new Set(selectedAtoms);
			selectedArrows = new Set(selectedArrows);
			selectedBonds = new Set(selectedBonds);
			selectedLonePairs = new Set(selectedLonePairs);
		}
	}
	
	function selectAll() {
		// Select all atoms, bonds, arrows, and lone pairs
		selectedAtoms.clear();
		selectedArrows.clear();
		selectedBonds.clear();
		selectedLonePairs.clear();
		
		atoms.forEach(atom => selectedAtoms.add(atom.id));
		arrows.forEach(arrow => selectedArrows.add(arrow.id));
		bonds.forEach(bond => selectedBonds.add(bond.id));
		lonePairs.forEach(lp => selectedLonePairs.add(lp.id));
		
		selectedAtoms = new Set(selectedAtoms);
		selectedArrows = new Set(selectedArrows);
		selectedBonds = new Set(selectedBonds);
		selectedLonePairs = new Set(selectedLonePairs);
		
		// Update atom visual feedback
		atoms = atoms.map(atom => ({
			...atom,
			selected: true
		}));
		
		console.log('Selected all - atoms:', selectedAtoms.size, 'bonds:', selectedBonds.size, 'arrows:', selectedArrows.size, 'lone pairs:', selectedLonePairs.size);
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
			
			const lonePairsInBox = lonePairs.filter(lonePair => 
				isLonePairInBox(lonePair, minX, maxX, minY, maxY)
			);
			
			console.log('Box selection complete. Found atoms:', selectedInBox.length, 'arrows:', arrowsInBox.length, 'bonds:', bondsInBox.length, 'lone pairs:', lonePairsInBox.length);
			
			// Add to selection (or replace if not holding shift)
			if (!event.shiftKey) {
				selectedAtoms.clear();
				selectedArrows.clear();
				selectedBonds.clear();
				selectedLonePairs.clear();
			}
			
			selectedInBox.forEach(atom => selectedAtoms.add(atom.id));
			arrowsInBox.forEach(arrow => selectedArrows.add(arrow.id));
			bondsInBox.forEach(bond => selectedBonds.add(bond.id));
			lonePairsInBox.forEach(lonePair => selectedLonePairs.add(lonePair.id));
			selectedAtoms = new Set(selectedAtoms); // Trigger reactivity
			selectedArrows = new Set(selectedArrows); // Trigger reactivity
			selectedBonds = new Set(selectedBonds); // Trigger reactivity
			selectedLonePairs = new Set(selectedLonePairs); // Trigger reactivity
			
			console.log('Total selected - atoms:', Array.from(selectedAtoms), 'arrows:', Array.from(selectedArrows), 'bonds:', Array.from(selectedBonds), 'lone pairs:', Array.from(selectedLonePairs));
			
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
			<button class="action-btn" on:click={() => { saveState(); atoms = []; bonds = []; arrows = []; lonePairs = []; selectedAtoms.clear(); selectedArrows.clear(); selectedBonds.clear(); selectedLonePairs.clear(); selectedAtoms = new Set(); selectedArrows = new Set(); selectedBonds = new Set(); selectedLonePairs = new Set(); }}>
				Clear All
			</button>
		</div>
		
		<div class="tool-group">
			<h3>Education</h3>
			<button class="tool-btn" on:click={() => showEducationalModal = true}>
				Chemistry Guide
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
				<g 
					on:click={(e) => {
						if (selectedTool === 'select') {
							e.stopPropagation();
							if (e.shiftKey) {
								// Toggle lone pair selection
								if (selectedLonePairs.has(lonePair.id)) {
									selectedLonePairs.delete(lonePair.id);
								} else {
									selectedLonePairs.add(lonePair.id);
								}
							} else {
								// Single selection
								selectedLonePairs.clear();
								selectedLonePairs.add(lonePair.id);
							}
							selectedLonePairs = new Set(selectedLonePairs);
						}
					}}
					style="cursor: pointer;"
				>
					<!-- Two dots for lone pair -->
					<circle 
						cx={position.x - 3} 
						cy={position.y} 
						r="2"
						fill={selectedLonePairs.has(lonePair.id) ? "#0066cc" : "#000000"}
						stroke={selectedLonePairs.has(lonePair.id) ? "#ffffff" : "none"}
						stroke-width={selectedLonePairs.has(lonePair.id) ? "1" : "0"}
					/>
					<circle 
						cx={position.x + 3} 
						cy={position.y} 
						r="2"
						fill={selectedLonePairs.has(lonePair.id) ? "#0066cc" : "#000000"}
						stroke={selectedLonePairs.has(lonePair.id) ? "#ffffff" : "none"}
						stroke-width={selectedLonePairs.has(lonePair.id) ? "1" : "0"}
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
		<div class="context-item" on:click={() => { saveState(); atoms = []; bonds = []; arrows = []; lonePairs = []; selectedAtoms.clear(); selectedArrows.clear(); selectedBonds.clear(); selectedLonePairs.clear(); hideContextMenu(); }}>
			Clear All
		</div>
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
					<h3>🏗️ Structure & Bonding Fundamentals</h3>
					<div class="structure-grid">
						<div class="structure-item">
							<strong>Lewis Structures:</strong> Show all valence electrons, lone pairs, and formal charges
						</div>
						<div class="structure-item">
							<strong>Resonance:</strong> Multiple valid electron arrangements (benzene, enolates, carbocations)
						</div>
						<div class="structure-item">
							<strong>Hybridization:</strong> sp³ (tetrahedral), sp² (trigonal), sp (linear)
						</div>
						<div class="structure-item">
							<strong>VSEPR:</strong> Electron pair repulsion determines molecular geometry
						</div>
					</div>
				</div>
				
				<div class="info-section">
					<h3>🔬 Periodic Table Trends</h3>
					<div class="trend-grid">
						<div class="trend-item">
							<strong>Electronegativity:</strong> F &gt; O &gt; N &gt; Cl &gt; Br &gt; I &gt; S &gt; C &gt; H<br>
							<em>Higher electronegativity = stronger electron pull</em>
						</div>
						<div class="trend-item">
							<strong>Atomic Size:</strong> H &lt; C &lt; N &lt; O &lt; F (across period)<br>
							<em>Smaller atoms = stronger bonds, higher electronegativity</em>
						</div>
						<div class="trend-item">
							<strong>Bond Strength:</strong> C-F &gt; C-O &gt; C-N &gt; C-C &gt; C-H<br>
							<em>Electronegativity difference affects bond polarity</em>
						</div>
					</div>
				</div>
				
				<div class="info-section">
					<h3>🌊 Electron Distribution & Orbitals</h3>
					<div class="orbital-grid">
						<div class="orbital-item">
							<strong>HOMO (Highest Occupied):</strong> Where electrons come from → nucleophile behavior
						</div>
						<div class="orbital-item">
							<strong>LUMO (Lowest Unoccupied):</strong> Where electrons go → electrophile behavior
						</div>
						<div class="orbital-item">
							<strong>Energy Gap:</strong> Small HOMO-LUMO gap = more reactive molecule
						</div>
						<div class="orbital-item">
							<strong>Charge Density:</strong> δ+ and δ− regions predict reaction sites
						</div>
					</div>
				</div>
				
				<div class="info-section">
					<h3>⚡ Energy Considerations</h3>
					<div class="energy-grid">
						<div class="energy-item thermo">
							<h4>Thermodynamics</h4>
							<p><strong>ΔG &lt; 0:</strong> Favorable reaction</p>
							<p><strong>Bond energies:</strong> Stronger bonds = more stable products</p>
							<p><strong>Stability order:</strong> Aromatic &gt; conjugated &gt; isolated</p>
						</div>
						<div class="energy-item kinetic">
							<h4>Kinetics</h4>
							<p><strong>Activation energy:</strong> Height of energy barrier</p>
							<p><strong>Transition state:</strong> Highest energy point in mechanism</p>
							<p><strong>Rate-determining step:</strong> Slowest step controls overall rate</p>
						</div>
					</div>
				</div>
				
				<div class="info-section">
					<h3>⚡ Electronegativity & Reactivity</h3>
					<div class="reactivity-grid">
						<div class="reaction-type">
							<h4>Nucleophilic Attack</h4>
							<p><strong>Target:</strong> Electron-deficient carbons (δ+)</p>
							<p><strong>Attacker:</strong> Electron-rich species (lone pairs, π electrons)</p>
							<p><strong>Examples:</strong> O⁻, N:, :OH⁻ attacking C=O, C-X</p>
						</div>
						<div class="reaction-type">
							<h4>Electrophilic Attack</h4>
							<p><strong>Target:</strong> Electron-rich sites (π bonds, lone pairs)</p>
							<p><strong>Attacker:</strong> Electron-deficient species (H⁺, carbocations)</p>
							<p><strong>Examples:</strong> H⁺ attacking C=C, aromatic rings</p>
						</div>
					</div>
				</div>
				
				<div class="info-section">
					<h3>🔗 Bond Polarity & Synthesis Predictions</h3>
					<div class="polarity-grid">
						<div class="polarity-item">
							<strong>C-O Bonds:</strong> δ⁺C—δ⁻O<br>
							<em>Carbon is electrophilic → nucleophilic attack site</em>
						</div>
						<div class="polarity-item">
							<strong>C-N Bonds:</strong> δ⁺C—δ⁻N<br>
							<em>Less polar than C-O, but still electrophilic carbon</em>
						</div>
						<div class="polarity-item">
							<strong>C-X Bonds:</strong> δ⁺C—δ⁻X (X = F, Cl, Br, I)<br>
							<em>Good leaving groups, SN1/SN2 reaction sites</em>
						</div>
						<div class="polarity-item">
							<strong>C=O Double Bonds:</strong> δ⁺C=δ⁻O<br>
							<em>Highly electrophilic carbon, nucleophilic addition reactions</em>
						</div>
					</div>
					
					<div class="prediction-box">
						<h4>🎯 Synthesis Prediction Rules:</h4>
						<ul>
							<li><strong>Higher Δ(electronegativity) = more polar bond = more reactive</strong></li>
							<li><strong>δ⁺ carbons:</strong> Predict nucleophilic attack (OH⁻, NH₃, R⁻)</li>
							<li><strong>δ⁻ atoms:</strong> Potential leaving groups or proton abstractors</li>
							<li><strong>Multiple bonds:</strong> Addition reactions likely (C=C, C=O, C≡N)</li>
							<li><strong>Lone pairs:</strong> Nucleophilic centers for electrophilic attack</li>
						</ul>
					</div>
				</div>
				
				<div class="info-section">
					<h3>🎯 Synthesis Strategy</h3>
					<div class="strategy-list">
						<div class="strategy-item">
							<strong>Identify Electrophiles:</strong> Look for C bonded to electronegative atoms (O, N, halogens)
						</div>
						<div class="strategy-item">
							<strong>Identify Nucleophiles:</strong> Look for lone pairs, negative charges, π electrons
						</div>
						<div class="strategy-item">
							<strong>Bond Polarity:</strong> δ+ carbons are reaction sites for nucleophiles
						</div>
						<div class="strategy-item">
							<strong>Leaving Groups:</strong> Stable anions (halides, tosylate) facilitate reactions
						</div>
					</div>
				</div>
				
				<div class="info-section">
					<h3>🔄 SN1 vs SN2 Mechanisms</h3>
					<div class="mechanism-grid">
						<div class="mechanism-item sn1">
							<h4>SN1 (Substitution Nucleophilic Unimolecular)</h4>
							<p><strong>Rate:</strong> Depends only on substrate [R-X]</p>
							<p><strong>Mechanism:</strong> Two steps via carbocation intermediate</p>
							<p><strong>Stereochemistry:</strong> Racemization (both R and S products)</p>
							<p><strong>Substrate:</strong> 3° &gt; 2° &gt;&gt; 1° (carbocation stability)</p>
							<p><strong>Nucleophile:</strong> Weak nucleophiles work fine</p>
							<p><strong>Solvent:</strong> Polar protic (stabilizes carbocation)</p>
						</div>
						<div class="mechanism-item sn2">
							<h4>SN2 (Substitution Nucleophilic Bimolecular)</h4>
							<p><strong>Rate:</strong> Depends on both [R-X] and [Nu⁻]</p>
							<p><strong>Mechanism:</strong> One step, backside attack</p>
							<p><strong>Stereochemistry:</strong> Inversion of configuration</p>
							<p><strong>Substrate:</strong> 1° &gt; 2° &gt;&gt; 3° (sterics matter)</p>
							<p><strong>Nucleophile:</strong> Strong nucleophiles required</p>
							<p><strong>Solvent:</strong> Polar aprotic (doesn't solvate nucleophile)</p>
						</div>
					</div>
				</div>
				
				<div class="info-section">
					<h3>🎯 Nucleophiles & Electrophiles</h3>
					<div class="species-grid">
						<div class="species-column">
							<h4>Strong Nucleophiles</h4>
							<div class="species-list">
								<div class="species-item"><strong>OH⁻:</strong> Hydroxide ion</div>
								<div class="species-item"><strong>RO⁻:</strong> Alkoxide ions</div>
								<div class="species-item"><strong>NH₂⁻:</strong> Amide ion</div>
								<div class="species-item"><strong>CN⁻:</strong> Cyanide ion</div>
								<div class="species-item"><strong>I⁻:</strong> Iodide (polarizable)</div>
							</div>
							
							<h4>Weak Nucleophiles</h4>
							<div class="species-list">
								<div class="species-item"><strong>H₂O:</strong> Water</div>
								<div class="species-item"><strong>ROH:</strong> Alcohols</div>
								<div class="species-item"><strong>NH₃:</strong> Ammonia</div>
								<div class="species-item"><strong>F⁻:</strong> Fluoride (small, hard to polarize)</div>
							</div>
						</div>
						
						<div class="species-column">
							<h4>Common Electrophiles</h4>
							<div class="species-list">
								<div class="species-item"><strong>R₃C⁺:</strong> Carbocations (3° &gt; 2° &gt; 1°)</div>
								<div class="species-item"><strong>R-X:</strong> Alkyl halides</div>
								<div class="species-item"><strong>H⁺:</strong> Protons (acids)</div>
								<div class="species-item"><strong>C=O:</strong> Carbonyl carbons</div>
								<div class="species-item"><strong>NO₂⁺:</strong> Nitronium ion</div>
							</div>
							
							<h4>Good Leaving Groups</h4>
							<div class="species-list">
								<div class="species-item"><strong>I⁻ &gt; Br⁻ &gt; Cl⁻ &gt; F⁻:</strong> Halides</div>
								<div class="species-item"><strong>TsO⁻:</strong> Tosylate</div>
								<div class="species-item"><strong>H₂O:</strong> In acidic conditions</div>
								<div class="species-item"><strong>N₂:</strong> From diazonium salts</div>
							</div>
						</div>
					</div>
				</div>
				
				<div class="info-section">
					<h3>🧪 Acid/Base Effects on Reactions</h3>
					<div class="reaction-conditions">
						<div class="condition-item acidic">
							<h4>Acidic Conditions (Low pH)</h4>
							<ul>
								<li><strong>Protonates nucleophiles:</strong> Makes them less reactive</li>
								<li><strong>Creates better leaving groups:</strong> -OH₂⁺ instead of -OH</li>
								<li><strong>Favors SN1:</strong> Stabilizes carbocation intermediates</li>
								<li><strong>Examples:</strong> Alcohol substitution, ether formation</li>
							</ul>
						</div>
						<div class="condition-item basic">
							<h4>Basic Conditions (High pH)</h4>
							<ul>
								<li><strong>Deprotonates acids:</strong> Creates nucleophilic anions</li>
								<li><strong>Enhances nucleophilicity:</strong> OH⁻ stronger than H₂O</li>
								<li><strong>Favors SN2:</strong> Strong nucleophiles work better</li>
								<li><strong>Examples:</strong> Williamson ether synthesis, saponification</li>
							</ul>
						</div>
					</div>
				</div>
				
				<div class="info-section">
					<h3>🛡️ Stability Factors</h3>
					<div class="stability-grid">
						<div class="stability-item">
							<strong>Resonance Stabilization:</strong> Delocalized electrons (benzene, enolates, carbocations)
						</div>
						<div class="stability-item">
							<strong>Aromaticity:</strong> Hugely stabilizing, 4n+2 π electrons in ring
						</div>
						<div class="stability-item">
							<strong>Inductive Effects:</strong> Electron-withdrawing (-NO₂, -CF₃) vs donating (-CH₃, -NH₂)
						</div>
						<div class="stability-item">
							<strong>Hyperconjugation:</strong> σ-bond overlap stabilizes carbocations/radicals
						</div>
						<div class="stability-item">
							<strong>Sterics:</strong> Bulky groups create strain, block reactions
						</div>
					</div>
				</div>
				
				<div class="info-section">
					<h3>🧪 Experimental Conditions</h3>
					<div class="conditions-grid">
						<div class="condition-factor">
							<h4>Temperature Effects</h4>
							<p><strong>Higher T:</strong> Favors entropy (more products), faster kinetics</p>
							<p><strong>Lower T:</strong> Favors enthalpy (stronger bonds), selectivity</p>
						</div>
						<div class="condition-factor">
							<h4>Solvent Effects</h4>
							<p><strong>Polar protic:</strong> H-bonding, stabilizes anions (SN1 favored)</p>
							<p><strong>Polar aprotic:</strong> No H-bonding, naked anions (SN2 favored)</p>
							<p><strong>Nonpolar:</strong> Dissolves organics, radical reactions</p>
						</div>
						<div class="condition-factor">
							<h4>Catalysts</h4>
							<p><strong>Acid catalysis:</strong> Protonates leaving groups, activates carbonyls</p>
							<p><strong>Base catalysis:</strong> Deprotonates, creates nucleophiles</p>
							<p><strong>Lewis acids:</strong> Accept electron pairs (AlCl₃, BF₃)</p>
						</div>
						<div class="condition-factor">
							<h4>Concentration</h4>
							<p><strong>High [substrate]:</strong> Favors unimolecular (SN1, E1)</p>
							<p><strong>High [nucleophile]:</strong> Favors bimolecular (SN2, E2)</p>
						</div>
					</div>
				</div>
				
				<div class="info-section">
					<h3>📊 Common Functional Groups</h3>
					<div class="functional-groups">
						<div class="fg-item"><strong>C=O:</strong> Electrophilic carbon, nucleophilic oxygen</div>
						<div class="fg-item"><strong>C-X:</strong> Electrophilic carbon, good leaving group</div>
						<div class="fg-item"><strong>C=C:</strong> Nucleophilic π electrons</div>
						<div class="fg-item"><strong>N:</strong> Nucleophilic lone pair</div>
						<div class="fg-item"><strong>O-H:</strong> Both nucleophilic and electrophilic</div>
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
	
	/* Educational Modal */
	.modal-overlay {
		position: fixed;
		top: 0;
		left: 0;
		width: 100%;
		height: 100%;
		background: rgba(0, 0, 0, 0.5);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 2000;
	}
	
	.modal-content {
		background: white;
		border-radius: 8px;
		max-width: 800px;
		max-height: 80vh;
		overflow-y: auto;
		box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
	}
	
	.modal-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 20px 30px;
		border-bottom: 1px solid #eee;
		background: #f8f9fa;
		border-radius: 8px 8px 0 0;
	}
	
	.modal-header h2 {
		margin: 0;
		color: #333;
		font-size: 24px;
	}
	
	.close-btn {
		background: none;
		border: none;
		font-size: 28px;
		cursor: pointer;
		color: #666;
		width: 32px;
		height: 32px;
		border-radius: 50%;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	
	.close-btn:hover {
		background: #f0f0f0;
		color: #333;
	}
	
	.modal-body {
		padding: 30px;
	}
	
	.info-section {
		margin-bottom: 30px;
	}
	
	.info-section h3 {
		color: #0066cc;
		margin: 0 0 15px 0;
		font-size: 18px;
		border-bottom: 2px solid #e3f2fd;
		padding-bottom: 8px;
	}
	
	.trend-grid {
		display: grid;
		gap: 15px;
	}
	
	.trend-item {
		padding: 15px;
		background: #f8f9fa;
		border-radius: 6px;
		border-left: 4px solid #0066cc;
	}
	
	.trend-item strong {
		color: #333;
	}
	
	.trend-item em {
		color: #666;
		font-size: 14px;
	}
	
	.reactivity-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 20px;
	}
	
	.reaction-type {
		padding: 20px;
		background: #fff3e0;
		border-radius: 8px;
		border: 1px solid #ffcc02;
	}
	
	.reaction-type h4 {
		margin: 0 0 10px 0;
		color: #e65100;
	}
	
	.reaction-type p {
		margin: 8px 0;
		font-size: 14px;
		line-height: 1.4;
	}
	
	.strategy-list {
		display: grid;
		gap: 12px;
	}
	
	.strategy-item {
		padding: 12px 15px;
		background: #e8f5e8;
		border-radius: 6px;
		border-left: 4px solid #4caf50;
		font-size: 14px;
	}
	
	.strategy-item strong {
		color: #2e7d32;
	}
	
	.functional-groups {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
		gap: 10px;
	}
	
	.fg-item {
		padding: 10px;
		background: #f3e5f5;
		border-radius: 6px;
		font-size: 14px;
		text-align: center;
		border: 1px solid #ce93d8;
	}
	
	.fg-item strong {
		color: #7b1fa2;
	}
	
	.polarity-grid {
		display: grid;
		gap: 15px;
		margin-bottom: 20px;
	}
	
	.polarity-item {
		padding: 15px;
		background: #e3f2fd;
		border-radius: 6px;
		border-left: 4px solid #1976d2;
	}
	
	.polarity-item strong {
		color: #1565c0;
	}
	
	.polarity-item em {
		color: #666;
		font-size: 14px;
	}
	
	.prediction-box {
		background: #f1f8e9;
		border: 2px solid #66bb6a;
		border-radius: 8px;
		padding: 20px;
		margin-top: 15px;
	}
	
	.prediction-box h4 {
		margin: 0 0 15px 0;
		color: #2e7d32;
		font-size: 16px;
	}
	
	.prediction-box ul {
		margin: 0;
		padding-left: 20px;
	}
	
	.prediction-box li {
		margin-bottom: 8px;
		line-height: 1.4;
		font-size: 14px;
	}
	
	.prediction-box li strong {
		color: #1b5e20;
	}
	
	.mechanism-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 20px;
		margin-bottom: 20px;
	}
	
	.mechanism-item {
		padding: 20px;
		border-radius: 8px;
		border: 2px solid;
	}
	
	.mechanism-item.sn1 {
		background: #fce4ec;
		border-color: #e91e63;
	}
	
	.mechanism-item.sn2 {
		background: #e8f5e8;
		border-color: #4caf50;
	}
	
	.mechanism-item h4 {
		margin: 0 0 15px 0;
		font-size: 16px;
	}
	
	.mechanism-item.sn1 h4 {
		color: #c2185b;
	}
	
	.mechanism-item.sn2 h4 {
		color: #388e3c;
	}
	
	.mechanism-item p {
		margin: 8px 0;
		font-size: 14px;
		line-height: 1.4;
	}
	
	.species-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 30px;
	}
	
	.species-column h4 {
		margin: 0 0 12px 0;
		color: #0066cc;
		font-size: 16px;
		border-bottom: 1px solid #e3f2fd;
		padding-bottom: 6px;
	}
	
	.species-list {
		margin-bottom: 25px;
	}
	
	.species-item {
		padding: 8px 12px;
		background: #f8f9fa;
		border-radius: 4px;
		margin-bottom: 6px;
		font-size: 14px;
		border-left: 3px solid #0066cc;
	}
	
	.species-item strong {
		color: #1565c0;
	}
	
	.reaction-conditions {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 20px;
	}
	
	.condition-item {
		padding: 20px;
		border-radius: 8px;
		border: 2px solid;
	}
	
	.condition-item.acidic {
		background: #fff3e0;
		border-color: #ff9800;
	}
	
	.condition-item.basic {
		background: #e8f5e8;
		border-color: #4caf50;
	}
	
	.condition-item h4 {
		margin: 0 0 15px 0;
		font-size: 16px;
	}
	
	.condition-item.acidic h4 {
		color: #f57c00;
	}
	
	.condition-item.basic h4 {
		color: #388e3c;
	}
	
	.condition-item ul {
		margin: 0;
		padding-left: 20px;
	}
	
	.condition-item li {
		margin-bottom: 8px;
		font-size: 14px;
		line-height: 1.4;
	}
	
	.structure-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
		gap: 15px;
	}
	
	.structure-item {
		padding: 15px;
		background: #f3e5f5;
		border-radius: 6px;
		border-left: 4px solid #9c27b0;
		font-size: 14px;
	}
	
	.structure-item strong {
		color: #7b1fa2;
	}
	
	.orbital-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
		gap: 15px;
	}
	
	.orbital-item {
		padding: 15px;
		background: #e1f5fe;
		border-radius: 6px;
		border-left: 4px solid #0277bd;
		font-size: 14px;
	}
	
	.orbital-item strong {
		color: #0277bd;
	}
	
	.energy-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 20px;
	}
	
	.energy-item {
		padding: 20px;
		border-radius: 8px;
		border: 2px solid;
	}
	
	.energy-item.thermo {
		background: #fff8e1;
		border-color: #ffc107;
	}
	
	.energy-item.kinetic {
		background: #fce4ec;
		border-color: #e91e63;
	}
	
	.energy-item h4 {
		margin: 0 0 12px 0;
		font-size: 16px;
	}
	
	.energy-item.thermo h4 {
		color: #f57c00;
	}
	
	.energy-item.kinetic h4 {
		color: #c2185b;
	}
	
	.energy-item p {
		margin: 6px 0;
		font-size: 14px;
	}
	
	.stability-grid {
		display: grid;
		gap: 12px;
	}
	
	.stability-item {
		padding: 12px 15px;
		background: #f1f8e9;
		border-radius: 6px;
		border-left: 4px solid #66bb6a;
		font-size: 14px;
	}
	
	.stability-item strong {
		color: #2e7d32;
	}
	
	.conditions-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
		gap: 20px;
	}
	
	.condition-factor {
		padding: 18px;
		background: #f8f9fa;
		border-radius: 8px;
		border: 1px solid #dee2e6;
	}
	
	.condition-factor h4 {
		margin: 0 0 10px 0;
		color: #495057;
		font-size: 15px;
	}
	
	.condition-factor p {
		margin: 6px 0;
		font-size: 13px;
		line-height: 1.4;
	}
</style>