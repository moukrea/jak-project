# water-census (SPEC-refonte-eau.md §5.8) : inventaire hors ligne de l'eau, bureau seulement.
# A ce stade l'outil N'ECRIT AUCUN compagnon `.waterbake` : l'item 0 ne fait que RECENSER.
add_executable(water_bake main.cpp)
target_link_libraries(water_bake common fmt)
