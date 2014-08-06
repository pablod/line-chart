      getPixelCssProp: (element, propertyName) ->
        string = $window.getComputedStyle(element, null)
          .getPropertyValue(propertyName)
        return +string.replace(/px$/, '')

      getDefaultMargins: ->
        return {top: 20, right: 50, bottom: 60, left: 50}

      clean: (element) ->
        d3.select(element)
          .on('keydown', null)
          .on('keyup', null)
          .select('svg')
            .remove()

      bootstrap: (element, dimensions) ->
        d3.select(element).classed('chart', true)

        width = dimensions.width
        height = dimensions.height

        svg = d3.select(element).append('svg')
          .attr(
            width: width
            height: height
          )
          .append('g')
            .attr('transform', 'translate(' + dimensions.left + ',' + dimensions.top + ')')

        svg.append('defs')
          .attr('class', 'patterns')

        return svg

      createContent: (svg) ->
        svg.append('g').attr('class', 'content')

      createGlass: (svg, dimensions, handlers, axes, data, options, columnWidth) ->
        glass = svg.append('g')
          .attr(
            'class': 'glass-container'
            'opacity': 0
          )

        items = glass.selectAll('.scrubberItem')
          .data(data)
          .enter()
            .append('g')
              .attr('class', (s, i) -> "scrubberItem series_#{i}")

        g = items.append('g')
          .attr('class': (s, i) -> "rightTT")

        g.append('path')
          .attr(
            'class': (s, i) -> "scrubberPath series_#{i}"
            'y': '-7px'
            'fill': (s) -> s.color
          )

        this.styleTooltip(g.append('text')
          .style('text-anchor', 'start')
          .attr(
            'class': (d, i) -> "scrubberText series_#{i}"
            'height': '14px'
            'transform': 'translate(7, 3)'
            'text-rendering': 'geometric-precision'
          ))
          .text (s) -> s.label || s.y

        g2 = items.append('g')
          .attr('class': (s, i) -> "leftTT")

        g2.append('path')
          .attr(
            'class': (s, i) -> "scrubberPath series_#{i}"
            'y': '-7px'
            'fill': (s) -> s.color
          )

        this.styleTooltip(g2.append('text')
          .style('text-anchor', 'end')
          .attr(
            'class': (d, i) -> "scrubberText series_#{i}"
            'height': '14px'
            'transform': 'translate(-13, 3)'
            'text-rendering': 'geometric-precision'
          ))
          .text (s) -> s.label || s.y

        items.append('circle')
          .attr(
            'class': (s, i) -> "scrubberDot series_#{i}"
            'fill': 'white'
            'stroke': (s) -> s.color
            'stroke-width': '2px'
            'r': 4
          )

        glass.append('rect')
          .attr(
            class: 'glass'
            width: dimensions.width - dimensions.left - dimensions.right
            height: dimensions.height - dimensions.top - dimensions.bottom
          )
          .style('fill', 'white')
          .style('fill-opacity', 0.000001)
          .on('mouseover', ->
            handlers.onChartHover(svg, d3.select(d3.event.target), axes, data, options, columnWidth)
          )


      getDataPerSeries: (data, options) ->
        series = options.series
        axes = options.axes

        return [] unless series and series.length and data and data.length

        straightened = series.map (s, i) ->
          seriesData =
            index: i
            name: s.y
            values: []
            color: s.color
            axis: s.axis || 'y'
            xOffset: 0
            type: s.type
            thickness: s.thickness
            drawDots: s.drawDots isnt false

          if s.striped is true
            seriesData.striped = true

          if s.lineMode?
            seriesData.lineMode = s.lineMode

          if s.id
            seriesData.id = s.id

          data.filter((row) -> row[s.y]?).forEach (row) ->
            seriesData.values.push(
              x: row[options.axes.x.key]
              y: row[s.y]
              y0: 0
              axis: s.axis || 'y'
            )

          return seriesData

        if !options.stacks? or options.stacks.length is 0
          return straightened

        layout = d3.layout.stack()
          .values (s) -> s.values

        options.stacks.forEach (stack) ->
          return unless stack.series.length > 0
          layers = straightened.filter (s, i) -> s.id? and s.id in stack.series
          layout(layers)

        return straightened

      resetMargins: (dimensions) ->
        defaults = this.getDefaultMargins()

        dimensions.left = defaults.left
        dimensions.right = defaults.right
        dimensions.top = defaults.top
        dimensions.bottom = defaults.bottom

      adjustMargins: (svg, dimensions, options, data) ->
        this.resetMargins(dimensions)
        return unless data and data.length
        return unless options.series.length

        dimensions.left = this.getWidestTickWidth(svg, 'y')
        dimensions.right = this.getWidestTickWidth(svg, 'y2')

        if dimensions.right is 0 then dimensions.right = 20

        return if options.tooltip.mode is 'scrubber'
        series = options.series

        leftSeries = series.filter (s) -> s.axis isnt 'y2'
        leftWidest = this.getWidestOrdinate(data, leftSeries, options)
        dimensions.left = this.estimateSideTooltipWidth(svg, leftWidest, options.style.font).width + 20

        rightSeries = series.filter (s) -> s.axis is 'y2'
        return unless rightSeries.length

        rightWidest = this.getWidestOrdinate(data, rightSeries, options)
        dimensions.right = this.estimateSideTooltipWidth(svg, rightWidest, options.style.font).width + 20

      adjustMarginsForThumbnail: (dimensions, axes) ->
        dimensions.top = 1
        dimensions.bottom = 2
        dimensions.left = 0
        dimensions.right = 1

      estimateSideTooltipWidth: (svg, text, fontStyle) ->
        t = svg.append('text')
        t.text('' + text)
        this.styleTooltip(t, fontStyle)

        bbox = this.getTextBBox(t[0][0])
        t.remove()

        return bbox

      getTextBBox: (svgTextElement) ->
        return svgTextElement.getBBox()

      getWidestTickWidth: (svg, axisKey) ->
        max = 0
        bbox = this.getTextBBox

        ticks = svg.select(".#{axisKey}.axis").selectAll('.tick')
        ticks[0]?.map (t) -> max = Math.max(max, bbox(t).width)

        return max

      getWidestOrdinate: (data, series, options) ->
        widest = ''

        data.forEach (row) ->
          series.forEach (series) ->
            v = row[series.y]
            if series.axis? and options.axes[series.axis]?.labelFunction
              v = options.axes[series.axis].labelFunction(v)

            return unless v?

            if ('' + v).length > ('' + widest).length
              widest = v

        return widest
