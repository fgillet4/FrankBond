<script>
	import { onMount } from 'svelte';
	
	let atoms = [];
	let bonds = [];
	
	// Graph representation of the molecule
	let moleculeGraph = {
		nodes: new Map(), // atom id -> atom data
		edges: new Map(), // bond id -> {atomId1, atomId2, type}
		adjacency: new Map() // atom id -> Set of connected atom ids
	};
	
	let selectedElement = 'C';
	let selectedTool = 'atom';
	let tempBond = null;
	let svgElement;
	
	// Selection state
	let selectedAtoms = new Set();
	let isBoxSelecting = false;
	let boxStart = { x: 0, y: 0 };
	let boxEnd = { x: 0, y: 0 };
	
	// Pan and zoom state
	let zoom = 1;
	let pan = { x: 0, y: 0 };
	let isPanning = false;
	let lastPanPoint = { x: 0, y: 0 };
	let viewBox = { x: 0, y: 0, width: 800, height: 600 };
	
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
		}
	}
	
	function handleSVGMouseLeave() {
		debugCursor.visible = false;
	}
	
	function handleSVGClick(event) {
		if (isPanning || isBoxSelecting) return;
		
		const coords = getCanvasCoordinates(event);
		
		if (selectedTool === 'atom') {
			addAtom(coords.x, coords.y);
		} else if (selectedTool === 'select') {
			// Clear selection if clicking on empty space and not holding shift
			if (!event.shiftKey) {
				selectedAtoms.clear();
				selectedAtoms = new Set(selectedAtoms);
			}
		}
	}
	
	function addAtom(x, y) {
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
		if (selectedAtoms.size > 0) {
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
			selectedAtoms = new Set(selectedAtoms);
		}
	}
	
	function handleKeyDown(event) {
		if (event.key === 'Delete' || event.key === 'Backspace') {
			deleteSelected();
		}
	}
	
	// Pan and zoom handlers
	function handleMouseDown(event) {
		if (event.button === 1 || (event.button === 0 && event.altKey)) {
			// Middle mouse or Alt+left mouse for panning
			event.preventDefault();
			isPanning = true;
			lastPanPoint = { x: event.clientX, y: event.clientY };
			svgElement.style.cursor = 'grabbing';
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
		}
	}
	
	function handleMouseUp(event) {
		if (isPanning) {
			isPanning = false;
			svgElement.style.cursor = 'default';
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
			// Pan with trackpad scroll
			pan.x += event.deltaX / zoom;
			pan.y += event.deltaY / zoom;
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
		return () => {
			document.removeEventListener('keydown', handleKeyDown);
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
			<button class="action-btn" on:click={deleteSelected}>
				Delete Selected
			</button>
			<button class="action-btn" on:click={() => { atoms = []; bonds = []; }}>
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
			on:click={handleSVGClick}
			on:mousedown={handleMouseDown}
			on:mousemove={(e) => { handleMouseMove(e); handleSVGMouseMove(e); }}
			on:mouseleave={handleSVGMouseLeave}
			on:mouseup={handleMouseUp}
			on:wheel={handleWheel}
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
						stroke="#000000"
						stroke-width="2"
						fill="none"
						on:click={() => {
							if (selectedTool === 'bond') {
								const currentTypeIndex = bondTypes.indexOf(bond.type);
								const nextTypeIndex = (currentTypeIndex + 1) % bondTypes.length;
								bonds = bonds.map(b => 
									b.id === bond.id ? { ...b, type: bondTypes[nextTypeIndex] } : b
								);
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
						on:click={(e) => {
							if (isPanning) return;
							e.stopPropagation();
							if (selectedTool === 'bond') {
								if (tempBond) {
									completeBond(atom.id, e);
								} else {
									startBond(atom.id, e);
								}
							} else {
								selectAtom(atom.id);
							}
						}}
						style="cursor: pointer;"
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

<style>
	.app {
		display: flex;
		height: 100vh;
		font-family: Arial, sans-serif;
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
</style>