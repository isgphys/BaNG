function ParseData() {
    var addToLane = function (chart, item) {
        var name = item.lane;

        if (!chart.lanes[name])
            chart.lanes[name] = [];

        var lane = chart.lanes[name];
        var sublane = 0;
        while(isOverlapping(item, lane[sublane]))
            sublane++;

        if (!lane[sublane]) {
            lane[sublane] = [];
        }

        lane[sublane].push(item);
    };

    var isOverlapping = function(item, lane) {
        if (lane) {
            for (var i = 0; i < lane.length; i++) {
                var t = lane[i];
                var offset = 0; // time in milliseconds
                if ( item.start.getTime() < (Number(t.end.getTime()) + Number(offset))
                    && t.start.getTime() < (Number(item.end.getTime()) + Number(offset)) ) {
                    return true;
                }
            }
        }
        return false;
    };

    var parseData = function (data) {
        var i = 0, length = data.length, node;
        chart = { lanes: {} };

        for (i; i < length; i++) {
            addToLane(chart, data[i]);
        }
        return collapseLanes(chart);
    };

    var collapseLanes = function (chart) {
        var lanes = [], items = [], laneId = 0;
        var now = new Date();

        for (var laneName in chart.lanes) {
            var lane = chart.lanes[laneName];

            for (var i = 0; i < lane.length; i++) {
                var subLane = lane[i];

                // use custom label if defined, else laneName
                if (typeof(CustomLaneLabel) != "undefined") {
                    var LaneLabel = eval(CustomLaneLabel);
                } else {
                    var LaneLabel = (i === 0 ? laneName : '');
                }

                lanes.push({
                    id    : laneId,
                    label : LaneLabel,
                });

                for (var j = 0; j < subLane.length; j++) {
                    var item = subLane[j];

                    var bkpclass = item.info.BkpGroup;
                    if ( item.info.SystemBkp ) {
                        bkpclass += ' systembkp';
                    } else {
                        bkpclass += ' databkp';
                    }

                    items.push({
                        id    : item.id,
                        lane  : laneId,
                        start : item.start,
                        end   : item.end,
                        class : bkpclass,
                        info  : item.info
                    });
                }
                laneId++;
            }
        }
        return {lanes: lanes, items: items};
    }

    var generateRandomWorkItems = function () {
        var data = [];

        // read data from 'backups' variable
        for (var hostname in backups) {
            if (backups.hasOwnProperty(hostname)) {
                for (var i=0; i<backups[hostname].length; i++) {
                    var bkp = backups[hostname][i];
                    var tS = new Date(bkp.time_start);
                    var tE = new Date(bkp.time_stop);

                    var workItem = {
                        lane  : hostname,
                        start : tS,
                        end   : tE,
                        info  : {
                            TotFileSizeTrans : bkp.TotFileSizeTrans,
                            TotFileSize      : bkp.TotFileSize,
                            NumOfFiles       : bkp.NumOfFiles,
                            NumOfFilesTrans  : bkp.NumOfFilesTrans,
                            AvgFileSize      : bkp.AvgFileSize,
                            BkpFromPath      : bkp.BkpFromPath,
                            BkpFromHost      : bkp.BkpFromHost,
                            BkpToPath        : bkp.BkpToPath,
                            BkpToHost        : bkp.BkpToHost,
                            SystemBkp        : bkp.SystemBkp,
                            BkpGroup         : bkp.BkpGroup,
                            TimeStart        : getTime(tS),
                            TimeStop         : getTime(tE),
                            TimeElapsed      : time2human(tE-tS)
                        }
                    };
                    data.push(workItem);
                }
            }
        }
        return data;
    };

    return parseData(generateRandomWorkItems());
}

function time2human(time) {
    var time;
    var minutes = Math.round( time/60/1000 );
    if (minutes < 60) {
        time = minutes + "min";
    } else {
        time = Math.floor(minutes/60) + "h" + String('00'+minutes%60).slice(-2) + "min";
    }
    return time;
}

function getTime(date) {
    var date;
    var formatted_time = '';

    formatted_time += String('00'+date.getHours()  ).slice(-2) + ':';
    formatted_time += String('00'+date.getMinutes()).slice(-2);

    return formatted_time;
}

function DrawSwimlanes() {

    // Based on http://bl.ocks.org/1962173

    var data  = ParseData()
      , lanes = data.lanes
      , items = data.items
      , now   = new Date();

    var mainLaneHeight = 20;
    var miniLaneHeight = PlotMiniChart ? 12 : 0;

    var margin = {top: 20, right: 15, bottom: 15, left: 120}
      , width  = 1100 - margin.left - margin.right
      , height = lanes.length * (mainLaneHeight+miniLaneHeight) - margin.top - margin.bottom
      , miniHeight = lanes.length * miniLaneHeight + 50
      , mainHeight = height - miniHeight - 50;

    var x = d3.time.scale()
        .domain([d3.time.sunday(d3.min(items, function(d) { return d.start; })),
                 new Date().setHours(now.getHours()+1)])
        .range([0, width]);
    var x1  = d3.time.scale().range([0, width]);
    var ext = d3.extent(lanes, function(d) { return d.id; });
    var y1  = d3.scale.linear().domain([ext[0], ext[1] + 1]).range([0, mainHeight]);
    var y2  = d3.scale.linear().domain([ext[0], ext[1] + 1]).range([0, miniHeight]);

    // allow to customize initial interval displayed
    if( typeof CustomInterval === 'undefined' ) {
        // default view shows from current full hour 2 days ago to now plus one hour
        var InitialInterval = '[new Date(now.getFullYear(), now.getMonth(), now.getDate()-2, now.getHours(), 0, 0, 0), new Date().setHours(now.getHours()+1)]';
    } else {
        var InitialInterval = CustomInterval;
    }

    // draw the initial selection area
    var brush = d3.svg.brush()
        .x(x)
        .extent(eval(InitialInterval))
        .on("brush", display);

    // draw containers
    var chart = d3.select('#graph')
        .append('svg:svg')
        .attr('width', width + margin.right + margin.left)
        .attr('height', height + margin.top + margin.bottom)
        .attr('class', 'chart');

    chart.append('defs').append('clipPath')
        .attr('id', 'clip')
        .append('rect')
            .attr('width', width)
            .attr('height', mainHeight);

    // draw tooltip
    var tooltip = d3.select('body')
        .append('div')
        .attr('class', 'tooltip')
        .style('position', 'absolute')
        .style('z-index', '10')
        .style('visibility', 'hidden')
        .text('tooltip');

    // ====== draw main chart ======
    var main = chart.append('g')
        .attr('transform', 'translate(' + margin.left + ',' + margin.top + ')')
        .attr('width', width)
        .attr('height', mainHeight)
        .attr('class', 'main');

    // draw the lanes for the main chart
    main.append('g').selectAll('.laneLines')
        .data(lanes)
        .enter().append('line')
        .attr('x1', 0)
        .attr('y1', function(d) { return d3.round(y1(d.id)) + 0.5; })
        .attr('x2', width)
        .attr('y2', function(d) { return d3.round(y1(d.id)) + 0.5; })
        .attr('stroke', function(d) { return d.label === '' ? 'white' : 'lightgray' });

    main.append('g').selectAll('.laneText')
        .data(lanes)
        .enter().append('text')
        .text(function(d) { return d.label; })
        .attr('x', -10)
        .attr('y', function(d) { return y1(d.id + .5); })
        .attr('dy', '0.5ex')
        .attr('text-anchor', 'end')
        .attr('class', 'laneText');

    // draw the x axis
    var x1DateAxis = d3.svg.axis()
        .scale(x1)
        .orient('bottom')
        .ticks(d3.time.days, 1)
        .tickFormat(d3.time.format('%a %d'))
        .tickSize(6, 0, 0);
    main.append('g')
        .attr('transform', 'translate(0,' + mainHeight + ')')
        .attr('class', 'main axis date')
        .call(x1DateAxis);

    var x1MonthAxis = d3.svg.axis()
        .scale(x1)
        .orient('top')
        .ticks(d3.time.mondays, 1)
        .tickFormat(d3.time.format('%b - Week %W'))
        .tickSize(15, 0, 0);
    main.append('g')
        .attr('transform', 'translate(0,0.5)')
        .attr('class', 'main axis month')
        .call(x1MonthAxis)
        .selectAll('text')
            .attr('dx', 5)
            .attr('dy', 12);

    // draw a line representing today's date
    if (PlotTodaysLine) {
        main.append('line')
            .attr('y1', 0)
            .attr('y2', mainHeight)
            .attr('class', 'main todayLine')
            .attr('clip-path', 'url(#clip)');
    }

    // draw the items
    var itemRects = main.append('g')
        .attr('clip-path', 'url(#clip)');

    // ====== draw mini chart ======
    if (PlotMiniChart) {
        var mini = chart.append('g')
            .attr('transform', 'translate(' + margin.left + ',' + (mainHeight + 60) + ')')
            .attr('width', width)
            .attr('height', miniHeight)
            .attr('class', 'mini');

        // draw the lanes
        mini.append('g').selectAll('.laneLines')
            .data(lanes)
            .enter().append('line')
            .attr('x1', 0)
            .attr('y1', function(d) { return d3.round(y2(d.id)) + 0.5; })
            .attr('x2', width)
            .attr('y2', function(d) { return d3.round(y2(d.id)) + 0.5; })
            .attr('stroke', function(d) { return d.label === '' ? 'white' : 'lightgray' });
        mini.append('g').selectAll('.laneText')
            .data(lanes)
            .enter().append('text')
            .text(function(d) { return d.label; })
            .attr('x', -10)
            .attr('y', function(d) { return y2(d.id + .5); })
            .attr('dy', '0.5ex')
            .attr('text-anchor', 'end')
            .attr('class', 'laneText');

        // draw the items
        mini.append('g').selectAll('miniItems')
            .data(getPaths(items))
            .enter().append('path')
            .attr('class', function(d) { return 'miniItem ' + d.class; })
            .attr('d', function(d) { return d.path; });

        // invisible hit area to move around the selection window
        mini.append('rect')
            .attr('pointer-events', 'painted')
            .attr('width', width)
            .attr('height', miniHeight)
            .attr('visibility', 'hidden')
            .on('mouseup', moveBrush);

        // draw the x axis
        var xDateAxis = d3.svg.axis()
            .scale(x)
            .orient('bottom')
            .ticks(d3.time.mondays, (x.domain()[1] - x.domain()[0]) > 15552e6 ? 2 : 1)
            .tickFormat(d3.time.format('%b %d'))
            .tickSize(6, 0, 0);
        mini.append('g')
            .attr('transform', 'translate(0,' + miniHeight + ')')
            .attr('class', 'axis date')
            .call(xDateAxis);

        var xMonthAxis = d3.svg.axis()
            .scale(x)
            .orient('top')
            .ticks(d3.time.months, 1)
            .tickFormat(d3.time.format('%b %Y'))
            .tickSize(15, 0, 0);
        mini.append('g')
            .attr('transform', 'translate(0,0.5)')
            .attr('class', 'axis month')
            .call(xMonthAxis)
            .selectAll('text')
                .attr('dx', 5)
                .attr('dy', 12);

        // draw a line representing today's date
        if (PlotTodaysLine) {
            mini.append('line')
                .attr('x1', x(now) + 0.5)
                .attr('y1', 0)
                .attr('x2', x(now) + 0.5)
                .attr('y2', miniHeight)
                .attr('class', 'todayLine');
        }

        // draw selection area
        mini.append('g')
            .attr('class', 'x brush')
            .call(brush)
            .selectAll('rect')
                .attr('y', 1)
                .attr('height', miniHeight - 1);

        mini.selectAll('rect.background').remove();
    }
    display();

    function display () {

        var rects, labels
          , minExtent = brush.extent()[0]
          , maxExtent = brush.extent()[1]
          , visItems = items.filter(function (d) { return d.start < maxExtent && d.end > minExtent});

        if (PlotMiniChart) {
            mini.select('.brush').call(brush.extent([minExtent, maxExtent]));
        }

        x1.domain([minExtent, maxExtent]);

        if ((maxExtent - minExtent) > 1468800000) {
            x1DateAxis.ticks(d3.time.mondays, 1).tickFormat(d3.time.format('%a %d'))
            x1MonthAxis.ticks(d3.time.mondays, 1).tickFormat(d3.time.format('%b - Week %W'))
        }
        else if ((maxExtent - minExtent) > 172800000) {
            x1DateAxis.ticks(d3.time.days, 1).tickFormat(d3.time.format('%a %d'))
            x1MonthAxis.ticks(d3.time.mondays, 1).tickFormat(d3.time.format('%b - Week %W'))
        }
        else {
            x1DateAxis.ticks(d3.time.hours, 4).tickFormat(d3.time.format('%H:%M'))
            x1MonthAxis.ticks(d3.time.days, 1).tickFormat(d3.time.format('%b %e'))
        }

        // shift the today line
        if (PlotTodaysLine) {
            main.select('.main.todayLine')
                .attr('x1', x1(now) + 0.5)
                .attr('x2', x1(now) + 0.5);
        }

        // update the axis
        main.select('.main.axis.date').call(x1DateAxis);
        main.select('.main.axis.month').call(x1MonthAxis)
            .selectAll('text')
                .attr('dx', 5)
                .attr('dy', 12);

        // upate the item rects
        rects = itemRects.selectAll('rect')
            .data(visItems, function (d) { return d.id; })
            .attr('x', function(d) { return x1(d.start); })
            .attr('width', function(d) { return x1(d.end) - x1(d.start); });

        rects.enter().append('rect')
            .attr('x', function(d) { return x1(d.start); })
            .attr('y', function(d) { return y1(d.lane) + .1 * y1(1) + 0.5; })
            .attr('width', function(d) { return x1(d.end) - x1(d.start); })
            .attr('height', function(d) { return .8 * y1(1); })
            .attr('class', function(d) { return 'mainItem ' + d.class; })
            .on("click", onclick)
            .on("mouseover", tooltipShow)
            .on("mousemove", tooltipMove)
            .on("mouseout", tooltipHide);

        rects.exit().remove();

        // update the item labels
        labels = itemRects.selectAll('text')
            .data(visItems, function (d) { return d.id; })
            .attr('x', function(d) { return x1(Math.max(d.start, minExtent)) + 2; });

        labels.enter().append('text')
            .attr('x', function(d) { return x1(Math.max(d.start, minExtent)) + 2; })
            .attr('y', function(d) { return y1(d.lane) + .4 * y1(1) + 7; })
            .attr('text-anchor', 'start')
            .attr('class', 'itemLabel');

        labels.exit().remove();
    }

    function moveBrush () {
        var origin = d3.mouse(this)
          , point = x.invert(origin[0])
          , halfExtent = (brush.extent()[1].getTime() - brush.extent()[0].getTime()) / 2
          , start = new Date(point.getTime() - halfExtent)
          , end = new Date(point.getTime() + halfExtent);

        brush.extent([start,end]);
        display();
    }

    // generate a single path for each item class in the mini display for faster drawing
    function getPaths(items) {
        var paths = {}, d, offset = .5 * y2(1) + 0.5, result = [];
        for (var i = 0; i < items.length; i++) {
            d = items[i];
            if (!paths[d.class]) paths[d.class] = '';
            paths[d.class] += ['M',x(d.start),(y2(d.lane) + offset),'H',x(d.end)].join(' ');
        }

        for (var className in paths) {
            result.push({class: className, path: paths[className]});
        }

        return result;
    }

    // redirect to plotHost when clicking on data backups
    function onclick(d, i) {
        window.location = "/statistics/" + d.info.BkpFromHost + '/' + d.info.BkpFromPath.replace(/\//g,'_');
    }

    // functions to update tooltip when moving mouse
    function tooltipShow(d, i) {
        tooltip
            .style("visibility", "visible")
            .html( ""
                + "<table>"
                + "  <tr>"
                + "    <th>Size:</th>"
                + "    <td>" + d.info.TotFileSizeTrans + " transferred of a total of " + d.info.TotFileSize + "</td>"
                + "  </tr>"
                + "  <tr>"
                + "    <th>Files:</th>"
                + "    <td>" + d.info.NumOfFilesTrans + " files transferred of a total of " + d.info.NumOfFiles + "</td>"
                + "  </tr>"
                + "  <tr>"
                + "    <th>Ratio: </th>"
                + "    <td>" + d.info.AvgFileSize + " average file size</td>"
                + "  </tr>"
                + "  <tr>"
                + "    <th>Time:</th>"
                + "    <td>" + d.info.TimeStart + " &ndash; " + d.info.TimeStop + " (" + d.info.TimeElapsed + ")</td>"
                + "  </tr>"
                + "  <tr>"
                + "    <th>Path:</th>"
                + "    <td>" + d.info.BkpFromPath + "</td>"
                + "  </tr>"
                + "  <tr>"
                + "    <th>Group:</th>"
                + "    <td>" + d.info.BkpGroup + "</td>"
                + "  </tr>"
                + "  <tr>"
                + "    <th>Server:</th>"
                + "    <td>" + d.info.BkpToHost + "</td>"
                + "  </tr>"
                + "</table>"
            );
    }
    function tooltipHide(d, i) {
        tooltip
            .style("visibility", "hidden");
    }
    function tooltipMove(d, i) {
        tooltip
            .style("top", (d3.event.pageY-10)+"px")
            .style("left",(d3.event.pageX+30)+"px");
    }
}
