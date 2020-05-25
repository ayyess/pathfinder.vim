if !exists('g:pf_motions')
  let g:pf_motions = [
    \ {'motion': 'j', 'weight': 1, 'rweight': 0},
    \ {'motion': 'k', 'weight': 1, 'rweight': 0},
    \ {'motion': '(', 'weight': 2, 'rweight': 1},
    \ {'motion': ')', 'weight': 2, 'rweight': 1},
    \ {'motion': '{', 'weight': 2, 'rweight': 1},
    \ {'motion': '}', 'weight': 2, 'rweight': 1},
    \ {'motion': '#', 'weight': 3, 'rweight': 1},
    \ {'motion': '*', 'weight': 3, 'rweight': 1},
    \ {'motion': ']m', 'weight': 2, 'rweight': 1},
    \ {'motion': '[m', 'weight': 2, 'rweight': 1}
    \ ]
endif
if !exists('g:pf_motions_target_line_only')
  let g:pf_motions_target_line_only = [
    \ {'motion': '0', 'weight': 2, 'rweight': 2},
    \ {'motion': '^', 'weight': 2, 'rweight': 2},
    \ {'motion': '$', 'weight': 2, 'rweight': 2},
    \ {'motion': 'g_', 'weight': 3, 'rweight': 3},
    \ {'motion': '%', 'weight': 2, 'rweight': 2},
    \ {'motion': 'h', 'weight': 1, 'rweight': 1},
    \ {'motion': 'l', 'weight': 1, 'rweight': 1},
    \ {'motion': 'w', 'weight': 2, 'rweight': 0},
    \ {'motion': 'e', 'weight': 2, 'rweight': 0},
    \ {'motion': 'b', 'weight': 2, 'rweight': 0},
    \ {'motion': 'ge', 'weight': 3, 'rweight': 0},
    \ {'motion': 'W', 'weight': 2, 'rweight': 0},
    \ {'motion': 'E', 'weight': 2, 'rweight': 0},
    \ {'motion': 'B', 'weight': 2, 'rweight': 0},
    \ {'motion': 'gE', 'weight': 3, 'rweight': 0},
    \ ]
endif


function! PathfinderBegin()
  " Record the current cursor position
  let w:pf_start_line = line('.')
  let w:pf_start_col = virtcol('.')
endfunction
command PathfinderBegin call PathfinderBegin()


function! CalcG(node)
  " The G value can change based on the previously typed motions, so it must be
  " recalculated each time
  let node = a:node
  let g = 0

  while has_key(node, 'reached_from')
    if has_key(node, 'g')
      return g + node.g
    elseif has_key(node.reached_from, 'reached_by')
      \ && node.reached_from.reached_by == node.reached_by
      let g += node.reached_by.rweight
    else
      let g += node.reached_by.weight
    endif
    let node = node.reached_from
  endwhile

  return g
endfunction

function! CoordString(l, c)
  return a:l . ',' . a:c
endfunction

function! CreateNode(l, c, rb, rf)
  let key = CoordString(a:l, a:c)
  return {'key': key, 'line': a:l, 'col': a:c,
    \ 'reached_by': a:rb, 'reached_from': a:rf}
endfunction

function! DoMotion(node, child_nodes, motion)
  " Move to this node's character, then run the movement
  try
    execute 'silent! normal! ' . a:node['line'] . 'G' . a:node['col'] . '|' . a:motion['motion']
  catch
    " Ignore motions which cause an error
    return
  endtry

  if line('.') != a:node['line'] || virtcol('.') != a:node['col']
    " Only add the child node if the motion had an effect
    " This means we don't add things such as l at the end of a line
    call add(a:child_nodes, CreateNode(line('.'), virtcol('.'), a:motion, a:node))
  endif
endfunction

function! GetChildNodes(node)
  let child_nodes = []

  for motion in g:pf_motions
    call DoMotion(a:node, child_nodes, motion)
  endfor

  " If we are on the same line as the target position, use these too
  if a:node['line'] == w:pf_end_line
    for motion in g:pf_motions_target_line_only
      call DoMotion(a:node, child_nodes, motion)
    endfor
  endif

  return child_nodes
endfunction

function! Backtrack(final_node)
  let node = a:final_node
  let motion_sequence = []
  while has_key(node, 'reached_from')
    call add(motion_sequence, node.reached_by.motion)
    let node = node.reached_from
  endwhile

  call reverse(motion_sequence)
  return motion_sequence
endfunction

function! EchoKeys(motion_sequence)
  " Combine repeated motions into one with a count
  " Basically run length encoding
  let motion_string = ''
  let last_motion = ''
  let c = 0
  for motion in a:motion_sequence
    if last_motion !=# motion
      let motion_string = motion_string . (c > 1 ? c : '') . last_motion
      let last_motion = motion
      let c = 1
    else
      let c = c + 1
    endif
  endfor
  let motion_string = motion_string . (c > 1 ? c : '') . last_motion

  echom motion_string
endfunction

function! PathfinderRun()
  if !exists('w:pf_start_line') || !exists('w:pf_start_col')
    echom 'Please run :PathfinderBegin to set a start position first'
    return
  endif

  let w:pf_end_line = line('.')
  let w:pf_end_col = virtcol('.')

  let closed_nodes = {}
  let open_nodes = {}
  let motion_sequence = []

  let start_node = {'key': CoordString(w:pf_start_line, w:pf_start_col),
                   \ 'line': w:pf_start_line, 'col': w:pf_start_col}
  let open_nodes[start_node.key] = start_node

  while len(open_nodes) > 0
    " Find the node with the lowest value of g
    let current_node = values(open_nodes)[0]
    let current_node_g = CalcG(current_node)
    for node in values(open_nodes)
      if CalcG(node) < current_node_g
        let current_node = node
        let current_node_g = CalcG(node)
      endif
    endfor
    " Remove from open set
    unlet open_nodes[current_node.key]
    let closed_nodes[current_node.key] = current_node
    " The path to a closed node can't change, so we can cache the g value now
    let current_node.g = CalcG(current_node)

    if current_node.line == w:pf_end_line && current_node.col == w:pf_end_col
      " Found the target
      let motion_sequence = Backtrack(current_node)
      break
    endif

    for child_node in GetChildNodes(current_node)
      if has_key(closed_nodes, child_node.key) | continue | endif

      if has_key(open_nodes, child_node.key)
	      " Replace the existing node if this one has a lower g
      	if CalcG(child_node) < CalcG(open_nodes[child_node.key])
	        call extend(open_nodes[child_node.key], child_node)
      	endif
      else
        let open_nodes[child_node.key] = child_node
      endif
    endfor
  endwhile

  execute 'normal! ' . w:pf_end_line . 'G' . w:pf_end_col . '|'
  redraw
  if len(motion_sequence)
    call EchoKeys(motion_sequence)
  else
    echom 'No path found'
  endif
endfunction
command PathfinderRun call PathfinderRun()
