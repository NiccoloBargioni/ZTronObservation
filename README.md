# ZTronObservation

## Minimum Cost Spanning Arborescence 

This library uses GGST Fibonacci Heap-based Gabow's algorithm efficient implementation described in [this](https://mboether.com/assets/pdf/bother2023mst.pdf) paper to find the Minimum Cost Spanning Arborescence of a graph in `O(E+Vlog(V))` time, where `|E|` is the number of edges in the graph and `|V|` is the number of vertices. The code in this library is a Swift adaptation of [chistopher/arbok](https://github.com/chistopher/arbok/tree/5a38286e332552fe3c029afba57195e95182f90a)'s C++ version.

Performance was tested using a Macbook Air M1 2020 13", average runtime with 2k nodes was about 0.3s.
