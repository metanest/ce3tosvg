#!/usr/local/bin/ruby22
# -*- mode:ruby ; coding:utf-8 -*-
# vi:set ts=3 sw=3:
# vim:set sts=0 noet ft=ruby:

require "pp"

def scan_records io
	file_str = io.read
	spl_nl = file_str.split /[\n\r]+/
	spl_comma = spl_nl.map {|line|line.split /,/}
	spl_comma = spl_comma.flatten
	records = spl_comma.map {|s|s.lstrip}
	return records
end

def get_block records, block_key
	result = []
	indata = false
	records.each {|rec|
		if rec == "+#{block_key}" then
			indata = true
			next
		elsif rec == "-#{block_key}" then
			break
		end
		if indata then
			result << rec
		end
	}
	return result
end

def split_block records
	blks = []
	blk = []
	blkname = nil
	in_blk = false
	records.each {|rec|
		if in_blk then
			blk << rec
			if m = /\A\-([A-Z]+)\z/.match(rec) then
				if m[1] == blkname then
					blks << blk
					blk = []
					blkname = nil
					in_blk = false
				end
			end
		elsif m = /\A\+([A-Z]+)\z/.match(rec) then
			blk << rec
			blkname = m[1]
			in_blk = true
		end
	}
	return blks
end

def get_vars blk
	vars = {}
	blk_name = nil
	blk[1 ... -1].each {|rec|
		if blk_name then
			if rec == "-" + blk_name then
				blk_name = nil
			end
			next
		elsif m = /\A\+(.+)/.match(rec) then
			blk_name = m[1]
			next
		end
		if m = /\A([A-Z][0-9A-Z]*):(.*)/.match(rec) then
			vars[m[1]] = m[2]
		end
	}
	return vars
end

def get_svgopen blks
	wh = nil
	blks.each {|blk|
		if blk[0] == "+SHEETINFO" then
			vars = get_vars blk
			if vars["W"] and vars["H"] then
				w = vars["W"].to_i
				h = vars["H"].to_i
				wh = [w, h]
			end
			break
		end
	}

	return %{<svg xmlns="http://www.w3.org/2000/svg" xmlns:svg="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="#{wh[0]}" height="#{wh[1]}">\n}
end

def emit_tag blk
	vars = get_vars blk
	x, y = vars["X"].to_i, vars["Y"].to_i
	s = vars["S"]
	s ||= ""
	w = (s.length + 1) * 10
	if w < 20 then
		w = 20
	end

	case vars["D"]
	when "0"
		print %{  <g transform="translate(#{x} #{y})rotate(90)translate(-#{w})">\n}
	when "1"
		print %{  <g transform="translate(#{x} #{y})">\n}
	else
		raise
	end

	case vars["T"]
	when "0"
		print %{    <polygon points="0-5 0 5 #{w} 5 #{w}-5" fill="none" stroke="black"/>\n}
	when "1"
		print %{    <polygon points="0 0 5 5 #{w} 5 #{w}-5 5-5" fill="none" stroke="black"/>\n}
	when "2"
		print %{    <polygon points="0-5 0 5 #{w-5} 5 #{w} 0 #{w-5}-5" fill="none" stroke="black"/>\n}
	when "3"
		print %{    <polygon points="0 0 5 5 #{w-5} 5 #{w} 0 #{w-5}-5 5-5" fill="none" stroke="black"/>\n}
	else
		raise
	end

	print %{    <text x="#{0.5 * w.to_f}" y="3.5" text-anchor="middle" font-size="10">#{s}</text>\n}
	print %{  </g>\n}
end

def get_arc elem
	buf = ""
	vars = get_vars elem
	cx = vars["X"].to_i.to_f
	cy = vars["Y"].to_i.to_f
	r = vars["R"].to_i.to_f
	be = vars["B"].to_i
	en = vars["E"].to_i
	arc = en - be
	while arc < 0 do
		arc += 5760
	end
	be = - be.to_f * Math::PI / 2880.0
	en = - en.to_f * Math::PI / 2880.0
	x1 = cx + r * Math.cos(be)
	y1 = cy + r * Math.sin(be)
	x2 = cx + r * Math.cos(en)
	y2 = cy + r * Math.sin(en)
	if arc > 2880
		buf << %{      <path d="M #{x1} #{y1} A #{r} #{r} 0 1 0 #{x2} #{y2}" fill="none" stroke="black" stroke-linecap="round"/>\n}
	else
		buf << %{      <path d="M #{x1} #{y1} A #{r} #{r} 0 0 0 #{x2} #{y2}" fill="none" stroke="black" stroke-linecap="round"/>\n}
	end
	return buf
end

def get_poly elem
	buf = ""
	xs, ys = [], []
	fill_type = nil
	elem.each {|e|
		if m = /\A[XY]:(.*)/.match(e) then
			case m[0][0, 1]
			when "X" then
				xs << m[1].to_i
			when "Y" then
				ys << m[1].to_i
			else
				raise
			end
		elsif m = /\AF:(.*)/.match(e) then
			case m[1]
			when "-1" then
				fill_type = "none"
			when "1" then
				fill_type = "black"
			else
				raise
			end
		end
	}
	points = xs.zip(ys).join(" ")
	buf << %{      <polygon points="#{points}" fill="#{fill_type}" stroke="black" stroke-linejoin="round"/>\n}
	return buf
end

def get_circ elem
	buf = ""
	xs, ys = [], []
	elem.each {|e|
		if m = /\A[XY]:(.*)/.match(e) then
			case m[0][0, 1]
			when "X" then
				xs << m[1].to_i
			when "Y" then
				ys << m[1].to_i
			else
				raise
			end
		end
	}
	xmax = xs.max
	xmin = xs.min
	ymax = ys.max
	ymin = ys.min
	w = xmax - xmin
	h = ymax - ymin
	rx = 0.5 * w
	ry = 0.5 * h
	buf << %{      <rect x="#{xmin}" y="#{ymin}" width="#{w}" height="#{h}" rx="#{rx}" ry="#{ry}" fill="none" stroke="black"/>\n}
	return buf
end

def get_pin(elem, w, h)
	buf = ""
	vars = get_vars elem
	loc = vars["L"][0, 1]
	num = vars["L"][1 .. -1].to_i
	if vars["T"].include? "N" then
		case loc
		when "T" then
			x1 = 10 * num
			y1 = -10
			x2 = 10 * num
			y2 = -6
			cx = 10 * num
			cy = -3
		when "B" then
			x1 = 10 * num
			y1 = 10 * (h + 1)
			x2 = 10 * num
			y2 = 10 * h + 6
			cx = 10 * num
			cy = 10 * h + 3
		when "L" then
			x1 = -10
			y1 = 10 * num
			x2 = -6
			y2 = 10 * num
			cx = -3
			cy = 10 * num
		when "R" then
			x1 = 10 * (w + 1)
			y1 = 10 * num
			x2 = 10 * w + 6
			y2 = 10 * num
			cx = 10 * w + 3
			cy = 10 * num
		else
			raise
		end
		buf << %{      <line x1="#{x1}" y1="#{y1}" x2="#{x2}" y2="#{y2}" stroke="black" stroke-linecap="round"/>\n}
		buf << %{      <circle cx="#{cx}" cy="#{cy}" r="3" fill="none" stroke="black"/>\n}
	else
		case loc
		when "T" then
			x1 = 10 * num
			y1 = -10
			x2 = 10 * num
			y2 = 0
		when "B" then
			x1 = 10 * num
			y1 = 10 * (h + 1)
			x2 = 10 * num
			y2 = 10 * h
		when "L" then
			x1 = -10
			y1 = 10 * num
			x2 = 0
			y2 = 10 * num
		when "R" then
			x1 = 10 * (w + 1)
			y1 = 10 * num
			x2 = 10 * w
			y2 = 10 * num
		else
			raise
		end
		buf << %{      <line x1="#{x1}" y1="#{y1}" x2="#{x2}" y2="#{y2}" stroke="black" stroke-linecap="round"/>\n}
	end
	return buf
end

def get_lib lib
	width, height = nil, nil
	buf = ""
	split_block(lib).each {|blk|
		case blk[0]
		when "+PTN" then
			vars = get_vars blk
			width, height = vars["X"].to_i, vars["Y"].to_i
			ptn_blks = split_block blk[1 ... -1]
			ptn_blks.each {|elem|
				case elem[0]
				when "+L" then
					x, y = [], []
					elem.each {|e|
						if m = /\AX:(.*)/.match(e) then
							x << m[1].to_i
						end
						if m = /\AY:(.*)/.match(e) then
							y << m[1].to_i
						end
					}
					buf << %{      <line x1="#{x[0]}" y1="#{y[0]}" x2="#{x[1]}" y2="#{y[1]}" stroke="black" stroke-linecap="round"/>\n}
				when "+AR" then
					buf << get_arc(elem)
				when "+PG" then
					buf << get_poly(elem)
				when "+C" then
					buf << get_circ(elem)
				else
					# pass
				end
			}
		when "+COMP" then
			vars = get_vars blk
			w, h = vars["X"].to_i, vars["Y"].to_i
			comp_blks = split_block blk[1 ... -1]
			comp_blks.each {|elem|
				case elem[0]
				when "+PIN" then
					buf << get_pin(elem, w, h)
				else
					# pass
				end
			}
		else
			raise
		end
	}
	[width, height, buf]
end

def emit_component blk
	lib = get_block blk, "BSCH3_LIB_V.1.0"
	vars = get_vars blk
	x, y = vars["X"], vars["Y"]
	w, h, buf = get_lib lib
	print %{  <g transform="translate(#{x} #{y})">\n}
	transform_str = ""
	d = vars["DIR"].to_i
	case d & 3
	when 0
		transform_str = "translate(-#{w-1} -#{h-1})"
	when 1
		transform_str = "translate(0 -#{w-1})rotate(90)"
	when 2
		transform_str = "rotate(180)"
	when 3
		transform_str = "translate(-#{h-1})rotate(270)"
	else
		raise
	end
	if d & 4 == 4 then
		if d & 1 == 0 then
			transform_str = "translate(-#{w-1})scale(-1 1)" + transform_str
		else
			transform_str = "translate(-#{h-1})scale(-1 1)" + transform_str
		end
	end
	print %{    <g transform="#{transform_str}">\n}

	print buf

	print %{    </g>\n}
	#if vars["NH"] != "1" then
	#	n = vars["N"]
	#	nx = vars["NX"]
	#	ny = vars["NY"]
	#	print %{    <text x="#{nx}" y="#{ny}" >#{n}</text>\n}
	#end
	print %{  </g>\n}
end

def emit_svg blks
	print get_svgopen blks
	blks.each {|blk|
		case blk[0]
		when "+SHEETINFO" then
			#pass
		when "+WIRE" then
			vars = get_vars blk
			print %{  <line x1="#{vars["X1"]}" y1="#{vars["Y1"]}" x2="#{vars["X2"]}" y2="#{vars["Y2"]}" stroke="black" stroke-linecap="round"/>\n}
		when "+JUNCTION" then
			vars = get_vars blk
			print %{  <circle cx="#{vars["X"]}" cy="#{vars["Y"]}" r="2" fill="black"/>\n}
		when "+TAG" then
			emit_tag blk
		when "+COMPONENT" then
			emit_component blk
		else
			print "  <!-- #{blk[0]} -->\n"
		end
	}
	print "</svg>\n"
end

records = scan_records STDIN
ce3data = get_block records, "BSCH3_DATA_V.1.0"
blks = split_block ce3data
emit_svg blks
