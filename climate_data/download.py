#!/usr/bin/env python3
"""
Download reanalysis data using the python APIs. Should use the
Climate Data Store API and support various diverse datasets.
"""
import calendar

import numpy as np

# ECMWF constants
# NOTE: Note variables are technically on "levels" like hybrid
# level surface pressure but we still need 60 "levels".
# TODO: Fix the 12 hour thing. Works for some parameters (e.g. diabatic
# heating, has 3, 6, 9, 12) but other parameters have 0, 6, 12, 18.
TEMP_LEVS = [
    265, 270, 285, 300, 315, 330, 350, 370, 395, 430, 475, 530, 600, 700, 850
]
PRES_LEVS = [
    1, 2, 3, 5, 7, 10, 20, 30, 50, 70, 100, 125, 150, 175, 200, 225, 250,
    300, 350, 400, 450, 500, 550, 600, 650, 700, 750, 775, 800, 825, 850,
    875, 900, 925, 950, 975, 1000
]
ECMWF_LEVOPTS = {
    'ml': range(1, 137 + 1),
    'pl': PRES_LEVS,
    'pt': TEMP_LEVS,
    'pv': None,
    'sfc': None,
}
ECMWF_VAROPTS = {
    'q': '133.128',  # specific humidity
    'r': '157.128',  # relative humidity
    't': '130.128',  # temp
    'u': '131.128',  # u wind
    'v': '132.128',  # v wind
    'w': '135.128',  # w wind
    'z': '129.128',  # geopotential
    'p': '54.128',  # pressure (availble on potential temp and 2PVU surfaces)
    'pt': '3.128',  # potential temp (available on 2PVU surface)
    'vo': '138.128',  # relative vorticity
    'pv': '60.128',  # potential voriticy (available on pressure and potential temp)
    'sp': '134.128',  # surface pressure
    'msl': '151.128',  # sea level pressure
    'slp': '151.128',  # sea level pressure
    'msp': '152.128',  # model-level surface pressure (use for tdt etc., requires lev=1)
    'sst': '34.128',  # sea surface temp
    't2m': '167.128',  # 2 meter air temp
    'd2m': '168.128',  # 2 meter dew point
    'tdt': '110.162',  # diabatic temp tendency
    'precip': '228.128',  # precipitation accumulation
}


def era(
    params,
    stream,
    levtype,
    daterange=None,
    yearrange=None,
    monthrange=None,
    # dayrange=None,  # not yet used
    years=None,
    months=None,
    format='netcdf',
    forecast=False,
    step=12,
    levrange=None,
    levs=None,
    grid=None,
    hours=(0, 6, 12, 18),
    hour=None,
    res=None,
    box=None,
    filename='era.nc',
):
    """
    Retrieve ERA reanalysis data using the provided API. User must have a file
    named ``.ecmwfapirc`` in the home directory. Please see the API documentation
    for detalis, but it should look something like this:

    ::

        {
        "url"   : "https://api.ecmwf.int/v1",
        "key"   : "abcdefghijklmnopqrstuvwxyz",
        "email" : "email@gmail.com"
        }

    with the key found on your user/profile page on the ECMWF website.

    Parameters
    ----------
    params : str or list of str
        Variable name. Gets translated to MARS id name by dictionary below.
        Add to this from the `online GRIB table <https://rda.ucar.edu/datasets/ds627.0/docs/era_interim_grib_table.html>`_.
        Pay attention to *available groups*. If not available for the group
        you selected (e.g. pressure levs, moda), get ``ERROR 6 (MARS_EXPECTED_FIELDS)``.
        For rates of change of *parameterized* processes (i.e. diabatic) see
        `this link <https://confluence.ecmwf.int/pages/viewpage.action?pageId=57448466>`_.

    Other parameters
    ----------------
    stream : {'oper', 'moda', 'mofm', 'mdfa', 'mnth'}
        The data stream.
    levtype : {'ml', 'pl', 'sfc', 'pt', 'pv'}
        The level type (model, pressure, surface, potential temp, or 2 PVU surface).
    levrange : float or (float, float), optional
        The individual level or range of levels.
    levs : float or ndarray, optional
        The individual level or list of levels.
    yearrange : int or (int, int)
        The individual year or range of years.
    years : int or ndarray, optional
        The individual year or list of years.
    monthrange : int or (int, int), optional
        The individual month or range of months.
    months : int or ndarray, optional
        The individual month or list of months.
    daterange : (datetime.datetime, datetime.datetime), optional
        The range of dates.
    hours : {0, 6, 12, 18} or list thereof, optional
        The hour(s) (UTC) of observation.
    forecast : bool, optional
        Whether to use forecast `'fc'` or analysis `'an'` data.
    grid : str, optional
        The grid type. The default is ``N32`` which returns data on 64 latitudes.
    res : float, optional
        The grid resolution in degrees (alternative to `grid`). Closest match is chosen.
    box : str or length-4 list of float, optional
        The region name or the ``(west, south, east, north)`` boundaries`` boundaries.
    format : {'grib1', 'grib2', 'netcdf'}, optional
        The output format.
    filename : str, optional
        The name of file output.

    Notes
    -----
    Some fields (seems true for most model fields) are not archived as monthly means
    for some reason! Have no idea why because it would need almost zero storage
    requirements. Also note some data is only available in forecast ``'fc'`` mode
    but not ``'an'`` analysis mode, e.g. diabatic heating.
    """  # noqa: E501
    # Data stream
    import ecmwfapi as ecmwf  # only do so inside function

    # Variable id conversion (see:
    # https://rda.ucar.edu/datasets/ds627.0/docs/era_interim_grib_table.html)
    if isinstance(params, str) or not np.iterable(params):
        params = (params,)
    params = [ECMWF_VAROPTS.get(p, None) for p in params]
    if None in params:
        raise ValueError('MARS ID for param unknown (consider adding to this script).')
    params = '/'.join(params)

    # Time selection as various ranges or lists
    # Priority. Use daterange as datetime or date objects
    if daterange is not None:
        if not np.iterable(daterange):
            daterange = (daterange,)  # want a single day
        if stream != 'oper':
            y0, m0, y1, m1 = (
                daterange[0].year,
                daterange[0].month,
                daterange[1].year,
                daterange[1].month,
            )
            N = max(y1 - y0 - 1, 0) * 12 + (13 - m0) + m1  # number of months in range
            dates = '/'.join(
                '%04d%02d00' % (y0 + (m0 + n - 1) // 12, (m0 + n - 1) % 12 + 1)
                for n in range(N)
            )
        else:
            # MARS will get calendar days in range
            dates = '/to/'.join(d.strftime('%Y%m%d') for d in daterange)

    # Alternative. List years/months desired, and if synoptic, get all days within
    else:
        # Year specification
        if years is not None:
            if not np.iterable(years):
                years = (years,)  # single month
        elif yearrange is not None:
            if not np.iterable(yearrange):
                years = (yearrange,)
            else:
                years = tuple(range(yearrange[0], yearrange[1] + 1))
        else:
            raise ValueError('You must use "years" or "yearrange" kwargs.')
        # Month specification (helpful for e.g. JJA data)
        if months is not None:
            if not np.iterable(months):
                months = (months,)  # single month
        elif monthrange is not None:
            if not np.iterable(monthrange):
                months = (monthrange, monthrange)
            else:
                months = tuple(range(monthrange[0], monthrange[1] + 1))
        else:
            months = tuple(range(1, 13))
        # Construct dates ranges
        if stream != 'oper':
            dates = '/'.join(
                '/'.join('%04d%02d00' % (y, m) for m in months) for y in years
            )
        else:
            dates = '/'.join(
                '/'.join(
                    '/'.join(
                        '%04d%02d%02d' % (y, m, i + 1)
                        for i in range(calendar.monthrange(y, m)[1])
                    )
                    for m in months
                )
                for y in years
            )

    # Level selection as range or list
    levopts = np.array(ECMWF_LEVOPTS.get(levtype))  # could be np.array(None)
    if not levopts:
        raise ValueError('Invalid level type. Choose from "pl", "pt", "pv", "sfc".')
    if levtype not in ('sfc', 'pv'):  # these have multiple options
        if levs is None and levrange is None:
            raise ValueError(
                'Must specify list of levels with the "levs" keyword, a range of '
                'levels with the "levrange" keyword, or a single level to either one.'
            )
        if levs is not None:
            levs = np.atleast_1d(levs)
        elif not np.iterable(levrange) or len(levrange) == 1:
            levs = np.atleast_1d(levrange)
        else:
            levs = levopts[(levopts >= levrange[0]) & (levopts <= levrange[1])]
        levs = '/'.join(str(l) for l in levs.flat)

    # Grid and time specifications
    # Box is specified as pre-defined region (e.g. string 'europe') or n/s/w/e boundary
    if res is not None:
        grid = '%.5f/%.5f' % (res, res)
    elif grid is None:
        grid = 'N32'
    if box is not None and not isinstance(box, str):
        box = '/'.join(str(b) for b in (box[3], box[0], box[2], box[1]))
    if not np.iterable(hours):
        hours = (hours,)
    hours = '/'.join(str(h).zfill(2) for h in hours)  # zfill padds 0s on left
    if forecast:
        dtype, step = 'fc', str(step)
    else:
        dtype, step = 'an', '0'

    # Server instructions
    # Can also spit raw output into GRIB; apparently ERA-Interim uses
    # bilinear interpolation to make grid of point obs, which makes sense,
    # because their reanalysis model just picks out point observations
    # from spherical harmonics; so maybe grid cell concept is dumb? Maybe
    # need to focus on just using cosine weightings, forget about rest?
    # Not really sure what happens in some situations: list so far:
    # 1. If you provide with variable string-name instead of numeric ID, MARS will
    #    search for correct one; if there is name ambiguity/conflict will throw error.
    # 2. On GUI framework, ECMWF only offers a few resolution options, but program
    #    seems to run when requesting custom resolutions like 5deg/5deg
    request = {
        'class': 'ei',  # ecmwf classifiction; choose ERA-Interim
        'expver': '1',
        'dataset': 'interim',  # thought we already did that; *shrug*
        'type': dtype,  # type of field; analysis 'an' or forecast 'fc'
        'resol': 'av',  # prevents truncation before transformation to geo grid
        'gaussian': 'reduced',
        'format': format,
        'step': step,  # NOTE: ignored for non-forecast type
        'grid': grid,  # 64 latitudes, i.e. T42 truncation
        'stream': stream,  # product monthly, raw, etc.
        'date': dates,
        'time': hours,
        'levtype': levtype,
        'param': params,
        'target': filename,  # save location
    }
    maxlen = max(map(len, request.keys()))
    if levs is not None:
        request.update(levelist=levs)
    if box is not None:
        request.update(area=box)
    if stream == 'oper':  # TODO: change?
        request.update(hour=hour)
    parts = (f'{k!r}: ' + ' ' * (maxlen - len(k)) + f'{v}' for k, v in request.items())
    print('MARS request:', *parts, sep='\n')
    server = ecmwf.ECMWFDataServer()
    server.retrieve(request)
    return request


def merra():
    """
    Download MERRA data. Is this possible?

    Warning
    -------
    Not yet implemented.
    """
    raise NotImplementedError


def ncar():
    """
    Download NCAR CFSL data. Is this possible?

    Warning
    -------
    Not yet implemented.
    """
    raise NotImplementedError
