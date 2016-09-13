function drawBarchart(data) {
    var w = $( window ).width() - 500;
    var h = 30 * data.length;
    var yaxis_offset = 350;
    var MaxValue = d3.max(data, function(d){ return parseFloat(d.value); });

    var x = d3.scale.log()
        .domain([1, MaxValue])
        .range([0, w]);
    var y = d3.scale.ordinal()
        .domain(d3.keys(data))
        .rangeBands([0,h]);

    var chart = d3.select("#graph")
        .append("svg:svg")
            .attr("class", "chart")
            .attr("witdh", w)
            .attr("height", y.rangeBand() * data.length);

    // bar chart
    chart.selectAll("rect")
            .data(data)
        .enter().append("svg:rect")
            .attr("y", function(d,i){ return y(i); })
            .attr("transform", "translate(" + yaxis_offset + ",0)")
            .attr("height", y.rangeBand())
            .attr("class", "rect")
            .on("click", onClick)
            .attr("width", function(d){ return x(d.value) });

    // labels
    chart.selectAll("label")
            .data(data)
        .enter().append("svg:text")
            .attr("transform", "translate(" + yaxis_offset + ",0)")
            .attr("x", function(d){ return x(d.value) })
            .attr("y", function(d,i) {return y(i)+y.rangeBand()/2;})
            .attr("text-anchor", "end")
            .attr("dx", -5)
            .attr("dy", ".35em")
            .attr("class", "label")
            .text(function(d) {return d.label;});

    // y axis
    var yScale = d3.scale.ordinal()
        .domain(data.map(function(d,i) {return (i+1) + '. ' + d.name; }))
        .rangeBands([0,h]);
    var yAxis = d3.svg.axis()
        .scale(yScale)
        .tickPadding(7)
        .orient("left");

    chart.append("g")
        .attr("class", "y axis")
        .attr("transform", "translate(" + yaxis_offset + ",0)")
        .call(yAxis);
};

function onClick(d, i) {
    window.location = d.url;
};
