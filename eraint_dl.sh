#!/usr/bin/env python3
#------------------------------------------------------------------------------#
# Get ERA-Interim diabatic heating data on model level coordinates, looping
# through several years.
# Param table: https://rda.ucar.edu/datasets/ds627.0/docs/era_interim_grib_table.html
#------------------------------------------------------------------------------#
# Initial
import climpy
import subprocess
import sys
import os
base = os.path.expanduser('~/data/eraint')

# Get levels every 50mb, starting 1000mb
# NOTE: See https://www.ecmwf.int/en/forecasts/documentation-and-suppor/correspondence-between-l91-and-l137-model-levels
# for approx model pressures. We select just 21.
# NOTE: See https://confluence.ecmwf.int/display/EMOS/N32
# for available Gaussian grids.
# L137 (ERA5)
# levs = [133, 123, 118, 114, 111, 108, 105, 98, 96, 93, 90, 87, 83, 79, 75, 68, 60, 48, 29] # NOTE: the last one is at 10mb, rest are 1000mb, 950mb, etc.
# L91 (ERA5?)
# levs = [88, 83, 80, 77, 75, 73, 71, 69, 67, 65, 63, 61, 59, 57, 55, 53, 49, 45, 39, 30, 19] # WARNING: off track by 65 (525mb, should be 550mb), then back on track by 53 (350mb)
# L60 (ERA-Interim)
# levs = [58, 54, 51, 49, 47, 45, 43, 41, 39, 37, 35, 33, 31, 29, 26, 22, 14] # 20 or so
# Instead just get every level, way easier to interpolate that way
levs = range(1,61) # all 60 of them, so we can interpolate easily

# Load
# NOTE: For now just get July and January values, store in same place
# NOTE: Full decade is only 1GB or so, so we store one file
hours = (0, 12) # only hours 0, 12 available; tdt is average over 12 hours it seems
years = [(1981, 1990), (1991, 2000), (2001, 2010)]
# For testing
# levs = 58
# hours = 12
# years = [(2010, 2010)]
for year in years:
    for month in (1,7):
        # Temperature tendency
        filename = f'{base}/mlevs/tdt_{year[0]:04d}-{year[1]:04d}_{month:02d}.grb2'
        print(f'\n\n\nTemperature tendency for years {year}, months {month}, file {filename}.')
        climpy.eraint(('tdt','msp'), 'oper', 'ml', levs=levs,
                yearrange=year, months=month,
                # days=1, # for testing
                # years=year, month=months,
                filename=filename, grid='F32',
                forecast=True, format='grib2',
                # forecast=True, format='netcdf',
                step=12, hours=hours)

        # Load hybrid-level 1 surface pressure, needed
        # for interpolation to isobars
        # filename = f'{base}/mlevs/msp_{year[0]:04d}-{year[1]:04d}_{month:02d}.grb2'
        # print(f'\n\n\nSurface pressure for years {year}, months {month}, file {filename}.')
        # climpy.eraint('msp', 'oper', 'ml', levs=1,
        #         yearrange=year, months=month,
        #         # days=1, # for testing
        #         # years=year, month=months,
        #         filename=filename, grid='F32',
        #         forecast=True, format='grib2',
        #         # forecast=True, format='netcdf',
        #         step=12, hours=hours)
