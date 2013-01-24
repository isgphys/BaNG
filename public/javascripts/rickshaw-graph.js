var PlotData;
d3.json("/plot.json", function(json) {
    PlotData = json;
    if (PlotData.error) return alert(PlotData.error);
    drawVisualization();
});

function drawVisualization() {
    var graph = new Rickshaw.Graph({
        element       : document.querySelector("#chart"),
        width         : 860,
        height        : 600,
        min           : -0.05,
        renderer      : 'line',   // area, stack, bar, line, scatterplot
        interpolation : 'linear', // linear, step-after, cardinal (default), basis
        stroke        : true,
        series        : PlotData,
    });
    var x_axis = new Rickshaw.Graph.Axis.Time( {
        graph : graph,
    });
    var y_axis = new Rickshaw.Graph.Axis.Y( {
        graph       : graph,
        orientation : 'left',
        element     : document.getElementById('chart_y_axis'),
    });

    graph.render();

    var legend = new Rickshaw.Graph.Legend({
        graph   : graph,
        element : document.querySelector('#chart_legend'),
    });
    var legend_toggle = new Rickshaw.Graph.Behavior.Series.Toggle({
        graph   : graph,
        legend  : legend,
    });
    var hoverDetail = new Rickshaw.Graph.HoverDetail( {
        graph      : graph,
        formatter: function(series, x, y) {
            // reformat timestamp
            var d = new Date(x*1000);
            var X = d.getMonth() + 1 + '/' + d.getDate() + ' ' + String('00'+d.getHours()).slice(-2) + ':' + String('00'+d.getMinutes()).slice(-2);
            // fetch datapoint from human-readable series
            var Y = PlotData.filter( function(d){ return d.name === series.name })[0].humanReadable.filter( function(d){ return d.x === x })[0].y;

            var content = '<span class="detail_swatch" style="background-color: ' + series.color + '"></span>';
            content    += series.name + '</br>';
            content    += Y + ' @ ' + X ;
            return content;
        }
    });
    var slider = new Rickshaw.Graph.RangeSlider({
        element : document.querySelector('#chart_slider'),
        graph   : graph,
    });
    var togglerForm = document.getElementById('chart_toggler');
    togglerForm.addEventListener('change', function(e) {
        var choice = e.target.value;

        if (choice == 'line') {
                graph.setRenderer('line');
                graph.offset = 'zero';
        } else {
                graph.setRenderer('stack');
                graph.offset = choice;
        }
        graph.render();
    }, false);
}
