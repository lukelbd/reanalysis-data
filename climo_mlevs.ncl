;------------------------------------------------------------------------------;
; This file interpolates data on model levels
; to pressure coordinates, then gets averages and stuff.
;------------------------------------------------------------------------------;
; Below were attempts with NCO and CDO after converting to NetCDF file
; NOTE: No clear way to do this with ncap2; ends up that coordinate
; names on var110 do not change *and* singleton dims are silently deleted.
; NOTE: All tendencies are 'accumulated from the beginning of the forecast'
; i.e. just shows the *difference* from beginning. So units are K/12 hours.
; NOTE: Impossible to delete a variable from file in NCL! And if you try
; to save to that name, coordinates etc. get renamed. Just delete afterward.
; See: https://www.ncl.ucar.edu/Support/talk_archives/2008/0492.html
; # Prep
; ncap2 -O -s 'tdt($time,$nhym,$lat,$lon) = var110(:,:,:,:)' tmp.nc tmp0.nc
; ncks --no-abc -O -C -x -v lev,var110 tmp.nc tmp.nc
; ncks -O -C --no-abc -x -v lev,var110 tmp.nc tmp.nc # the -C includes coordinate vars
; # Interpolate, or at least try to
; file=tdt_${year1a}-${year2a}_${month}.nc # final
; levs=$(seq 2500 2500 100000 | tr $'\n' ',') # interpolate here
; cdo $flags -genlevelbounds,ztop=101325,zbot=0 \
;   -ml2pl,$levs -remapbil,griddes.txt -invertlat tmp.nc $file
; [ $? -ne 0 ] && echo "Error: Changes failed." && exit 1
; ncatted -O -a units,plev,o,c,"mb" $file # do this *after* interpolation
;------------------------------------------------------------------------------;
; print("Reading initial file and interpolating...")
load "~/timescales-model/header.ncl"
exists("tdt_file") ; id is var110 (see downloads.py)
exists("msp_file") ; id is var152 (msp = model surface-level pressure)
exists("output")
; Load
; TODO: Load these into same file
print("Loading files")
msp_f = addfile(msp_file, "r")
msp = msp_f->LNSP_GDS4_HYBL ; hybrid level 1 surface pressure
timer(" * Time for loading msp")
tdt_f = addfile(tdt_file, "r")
tdt = tdt_f->TT_GDS4_HYBL
timer(" * Time for loading tdt")
; Scale the tendency
; Units are "accumulated change" over 12 hour forecast period, turn into K/s
; NOTE: If you print e.g. (var * 1), will look like dimensions/coordinates
; are lost! But what happens internally on assignment is the dimensions
; and coordinates are ***re-assigned*** to the result of the calculation!
tdt = tdt/(3600.0*12.0)
msp = exp(msp) ; to Pascals; for some numerical reason, logarithm is used
print("Average surface pressure:")
print(avg(msp))
tdt@units = "K/s"
tdt@long_name = "diabatic heating rate"
; New file
system("rm " + output + " 2>/dev/null") ; remove file
o = addfile(output, "c")
filedimdef(o, "time", -1, True) ; set unlimited

; Get the sigma-coordinates and center-coordinates for interpolation
; TODO: Why not copy to NetCDF first? Because files are really big.
; NOTE: Coordinates must be orders top-to-bottom! ERA-Interim does so by
; default, probably because when interpolated to pressure they
; become low-to-high pressure, which is convention.
p0 = tdt_f->P0 ; reference pressure in Pa, by which hyai is scaled
hyai = tdt_f->lv_HYBL_i2_a
hybi = tdt_f->lv_HYBL_i2_b
hyam = tdt_f->lv_HYBL1_a
hybm = tdt_f->lv_HYBL1_b
p0   = 101325.0 ; reference pressure
p0mb = 1013.25 ; in mb for function input

; Pressure levs and pressure lev bounds
; This replicates behavior of genlevelbounds in CDO
plev = todouble(fspan(25.0, 1000.0, 40))
plev!0 = "plev"
plev&plev = plev
plev@long_name = "pressure level"
plev@units = "mb"
; Borders
np = dimsizes(plev)
plev_b = (plev(1:) + plev(:np-2))/2.0 ; the in-between interfaces
plev_bnds = new((/np, 2/), double)
plev_bnds(:np-2,1) = plev_b
plev_bnds(1:,0)    = plev_b
plev_bnds(0,0)  = 0.0
plev_bnds(np-1,1) = 1013.25
plev_bnds!0 = "plev"
plev_bnds!1 = "bnds"
plev_bnds&plev = plev
plev_bnds@long_name = "pressure level boundaries"
plev_bnds@units = "mb"
; Coordinates
; TODO: Are names robust?
; NOTE: Get error if don't assign coordinates to singleton variables:
; Right hand side has no coordinate variable can not delete coordinate variable of a file
time = tdt_f->initial_time0_hours(0)
time!0 = "time"
time&time = time
lat = tdt_f->g4_lat_4
lat!0 = "lat"
lon = tdt_f->g4_lon_5(0)
lon!0 = "lon"
lon&lon = lon
o->time = time
o->plev = plev
o->plev_bnds = plev_bnds
o->lat = lat
o->lon = lon
nlat = dimsizes(lat)
timer(" * Time for other stuff")

; Interpolate
; Note could also use int2p, more low-level/flexible version, just like
; I use it to interpolate to theta coordinates. Annoying that hybrid A coords
; have to be in terms of reference pressure here.
; The '1' says to interpolate in linear space. The second 1 is unused. The
; False says not to extrapolate below surface pressure..
; NOTE: For some reason surface pressure must be in Pa, but reference
; pressure in mb. Maybe convention that levels always in mb, other stuff in Pa?
print("Interpolating")
tdt_p = vinth2p(tdt, hyam, hybm, plev, msp, 1, p0mb, 1, False)
tdt_p!1 = "plev" ; rename dimension; simple as that

; Average
tdt_p := dim_avg_n(tdt_p, 3) ; cannot do them at same time, because not consecutive
tdt_p := dim_avg_n(tdt_p, 0)
; Add back singleton dims
tdt_p := conform_dims((/1, np, nlat, 1/), tdt_p, (/1, 2/))
tdt_p!0 = "time"
tdt_p!1 = "plev"
tdt_p!2 = "lat"
tdt_p!3 = "lon"
tdt_p&time = time
tdt_p&plev = plev
tdt_p&lat = lat
tdt_p&lon = lon
copy_VarAtts(tdt, tdt_p)
timer(" * Time for interpolating")

; Save result
print("Saving result")
o->tdt = tdt_p ; write to new file
timer(" * Time for saving result")

