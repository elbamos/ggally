if(getRversion() >= "2.15.1") {
	utils::globalVariables(c(
		"lon", "lat", "Y1", "Y2", "group", "id", "midX", "midY",
		"lon1", "lat1", "lon2", "lat2"
	))
}

#' ggmapnetwork - Plot a network with ggplot2 suitable for overlay on a ggmap:: map ggplot, or other ggplot
#'
#' This is a descendent of the original ggnet function.  ggnet added the innovation of plotting the network geographically.
#' However, ggnet needed to be the first object in the ggplot chain.  ggnetworkmap does not.  If passed a ggplot object as its first argument,
#' ggneworkmap will plot on top of that chart, looking for vertex attributes \code{lon} and \code{lat} as coordinates.
#' Otherwise, ggnetworkmap will generate coordinates using the Fruchterman-Reingold algorithm.
#'
#' @export
#' @param gg an object of class \code{ggplot}.
#' @param data an object of class \code{igraph} or \code{network}. If the object is of class \code{igraph}, the \link[intergraph:asNetwork]{intergraph} package is used to convert it to class \code{network}.
#' @param size size of the network nodes. Defaults to 3. If the nodes are weighted, their area is proportionally scaled up to the size set by \code{size}.
#' @param alpha a level of transparency for nodes, vertices and arrows. Defaults to 0.75.
#' @param weight either \code{NULL}, the default, for unweighted nodes, or the unquoted name of a vertex attribute in \code{data}
#' @param node.group \code{NULL}, the default, or the unquoted name of a vertex attribute that will be used to determine the color of each node.
#' @param ring.group if not \code{NULL}, the default, the unquoted name of a vertex attribute that will be used to determine the color of each node border.
#' @param node.color If \code{node.group} is null, a character string specifying a color.  Otherwise, an object produced by a \code{scale_fill_} function from the \code{ggplot2} package.
#' @param ring.color If \code{ring.group} is not null, an object produced by a \code{scale_color_} function from the \code{ggplot2} package.  Ignored unless \code{ring.group} is set.
#' @param node.alpha transparency of the nodes. Inherits from \code{alpha}.
#' @param segment.alpha transparency of the vertex links. Inherits from \code{alpha}
#' @param segment.color color of the vertex links. Defaults to \code{"grey"}.
#' @param segment.size size of the vertex links, as a vector of values or as a single value. Defaults to 0.25.
#' @param great.circles whether to draw edges as great circles using the \code{geosphere} package.  Defaults to \code{FALSE}
#' @param arrow.size size of the vertex arrows for directed network plotting, in centimeters. Defaults to 0.
#' @param label.nodes label nodes with their vertex names attribute. If set to \code{TRUE}, all nodes are labelled. Also accepts a vector of character strings to match with vertex names.
#' @param label.size size of the labels.  Defaults to \code{size / 2}.
#' @param quantize.weights break node weights to quartiles. Fails when quartiles do not uniquely identify nodes.
#' @param subset.threshold delete nodes prior to plotting, based on \code{weight.method} < \code{subset.threshold}. If \code{weight.method} is unspecified, total degree (Freeman's measure) is used. Defaults to 0 (no subsetting).
#' @param ... other arguments supplied to geom_text for the node labels. Arguments pertaining to the title or other items can be achieved through ggplot2 methods.
#' @author Amos Elberg \email{amos.elberg@@gmail.com}
#' @author Original by Moritz Marbach \email{mmarbach@@mail.uni-mannheim.de}, Francois Briatte \email{f.briatte@@gmail.com}
#' @importFrom grid arrow
#' @importFrom geosphere gcIntermediate

ggnetworkmap <- function (
	gg,
	data,
	size = 3,
	alpha = 0.75,
	weight.method = NULL,
	node.group,
	node.color = NULL,
	node.alpha = NULL,
	ring.group,
	ring.color = NULL,
	segment.alpha = NULL,
	segment.group, # not enabled
	segment.color = "grey",
	great.circles = FALSE,
	segment.size = 0.25,
	arrow.size = 0,
	label.nodes = FALSE,
	label.size = size/2,
	quantize.weights = FALSE,
	subset.threshold = 0,
	...)
{


	GGally:::require_pkgs(c("intergraph", "network", "geosphere","grid","sna"))
	# intergraph   # igraph conversion
	# network      # vertex attributes
	# geosphere 	 # great circles
	# sna					 # layout graph if not fed a ggplot object

	# support for igraph objects
	net <- data
	if(class(net) == "igraph") {
		net = intergraph::asNetwork(net)
	}
	if(class(net) != "network")
		stop("net must be a network object of class 'network' or 'igraph'")

	# vertex attributes for weight detection
	vattr = network::list.vertex.attributes(net)

	# get arguments
	quartiles = quantize.weights
	labels    = label.nodes

	# alpha default
	inherit <- function(x) ifelse(is.null(x), alpha, x)
	# subset
	if(subset.threshold > 0) {
		network::delete.vertices(
			net,
			which(sna::degree(net, cmode = weight) < subset.threshold))
	}

	# get sociomatrix
	m <- network::as.matrix.network.adjacency(net)
	v_function = get("%v%", envir = as.environment("package:network"))

	if (missing(gg)) {
		gg <- ggplot()

		plotcord <- do.call("gplot.layout.fruchtermanreingold", list(m,layout.par = NULL))
		plotcord <- data.frame(plotcord)
		colnames(plotcord) = c("lon", "lat")
	} else {
		plotcord = data.frame(
			lon = as.numeric(v_function(net, "lon")),
			lat = as.numeric(v_function(net, "lat"))
		)

		# remove outliers
		# NOTE THIS MAY CAUSE FAILURE IF PUTTING IN VECTOR OR AS NODE OR EDGE GROUP
		plotcord$lon[ abs(plotcord$lon) > quantile(abs(plotcord$lon), .9, na.rm = TRUE) ] = NA
		plotcord$lat[ is.na(plotcord$lon) | abs(plotcord$lat) > quantile(abs(plotcord$lat), .9, na.rm = TRUE) ] = NA
		plotcord$lon[ is.na(plotcord$lat) ] = NA
	}

	point_aes <- list(
		x = substitute(lon),
		y = substitute(lat)
	)
	point_args <- list(
		alpha = substitute(inherit(node.alpha))
	)

	# get node groups
	if(!missing(node.group)) {
		plotcord$ngroup <-
			network::get.vertex.attribute(net, as.character(substitute(node.group)))
		point_aes$fill = substitute(ngroup)
	} else if (! missing(node.color)) {
		point_args$color <- substitute(node.color)
	} else {
		point_args$clor <- substitute( "black")
	}


	# rings
	if(!missing(ring.group)) {
		plotcord$rgroup <-
			network::get.vertex.attribute(net, as.character(substitute(ring.group)))
		point_aes$color <- substitute(rgroup)
		point_args$pch <- substitute(21)
	}

	# set vertex names
	plotcord$id <- as.character(network::get.vertex.attribute(net, "id"))
	if(is.logical(labels)) {
		if(!labels) {
			plotcord$id = ""
		}
	} else {
		plotcord$id[ -which(plotcord$id %in% labels) ] = ""
	}

	#
	#
	# Plot edges
	#
	#

	# get edgelist
	edglist <- network::as.matrix.network.edgelist(net)
	edges   <- data.frame(
		lat1 = plotcord[edglist[, 1], "lat"],
		lon1 = plotcord[edglist[, 1], "lon"],
		lat2 =  plotcord[edglist[, 2], "lat"],
		lon2 = plotcord[edglist[,2], "lon"])
	edges <- subset(edges,
									(! is.na(lat1)) &
										(! is.na(lat2)) &
										(! is.na(lon1)) &
										(! is.na(lon2)) &
										(! (lat1 == lat2 & lon2 == lon2))
	)

	edge_args <- list(size = substitute(segment.size),
										alpha = substitute(inherit(segment.alpha)),
										color = substitute(segment.color)
	)
	edge_aes <- list()

	if (!missing(arrow.size) & arrow.size > 0) 	edge_args$arrow <- substitute(grid::arrow(
		type   = "closed",
		length = unit(arrow.size, "cm")
	))

	# THIS IS IGNORING SEGMENT COLOR RIGHT NOW
	if (great.circles) {
		pts <- 1  # number of intermediate points for drawing great circles
		i <- 0 # used to keep track of groups when getting intermediate points for great circles

		edges <- plyr::ddply(.data = edges, .variables = c("lat1","lat2","lon1","lon2"),
												 .fun = function(x) {
												 	i <<- i + 1
												 	inter <- data.frame(geosphere::gcIntermediate(
												 		p1 = x[,c("lon1", "lat1")],
												 		p2 = x[,c("lon2", "lat2")],
												 		n = pts,
												 		addStartEnd = TRUE
												 	))

												 	inter$group <- i
												 	#												 	inter$sgroup <- x$sgroup
												 	inter
												 })
		edge_aes$x = substitute(lon)
		edge_aes$y = substitute(lat)
		edge_aes$group = substitute(group)
		edge_args$data = substitute(edges)
		edge_args$mapping <- do.call(aes, edge_aes)
		gg <- gg + do.call(geom_path, edge_args)
	} else {
		edge_aes$x = substitute(lon1)
		edge_aes$y = substitute(lat1)
		edge_aes$xend = substitute(lon2)
		edge_aes$yend = substitute(lat2)
		edge_args$data <- substitute(edges)
		edge_args$mapping = do.call(aes, edge_aes)
		gg <- gg + do.call(geom_segment, edge_args)
	}

	#
	#
	# Done drawing edges, time to draws nodes
	#
	#


	# custom weights: vertex attribute
	# null weighting
	sizer <- NULL
	if(missing(weight.method)) {
		point_args$size <- substitute(size)
	} else {
		# Setup weight-sizing
		# quartiles
		point_aes$size = substitute(weight)
		if(quartiles) {
			plotcord$weight.label <- cut(
				plotcord$weight,
				breaks         = quantile(plotcord$weight),
				include.lowest = TRUE,
				ordered        = TRUE
			)
			plotcord$weight <- as.integer(plotcord$weight.label)
			sizer <- scale_size_area(
				substitute(weight.method),
				max_size = size,
				labels   = levels(plotcord$weight.label)
			)
		} else {
			plotcord$weight <-
				network::get.vertex.attribute(net, as.character(substitute(weight.method)))
			# proportional scaling
			sizer <- scale_size_area(substitute(weight.method), max_size = size)
		}
	}

	#	Add points to plot

	point_args$data <- substitute(plotcord)
	point_args$mapping <- do.call(aes,point_aes	)
	gg <- gg + do.call(geom_point, point_args)
	if (!is.null(sizer)) gg <- gg + sizer
	if ("scale" %in% class(node.color)) gg <- gg + node.color
	if ("scale" %in% class(ring.color)) gg <- gg + ring.color

	# add text labels
	if(length(unique(plotcord$id)) > 1 | unique(plotcord$id)[1] != "") {
		gg <- gg + geom_text(aes(label = id), size = label.size, ...)
	}

	return(gg)
}