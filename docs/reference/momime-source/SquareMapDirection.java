package com.ndg.map;

/**
 * Named direction for movement over a square-cell map
 */
public enum SquareMapDirection
{
	/** north */
	NORTH (1),

	/** northeast */
	NORTHEAST (2),

	/** east */
	EAST (3),

	/** southeast */
	SOUTHEAST (4),

	/** south */
	SOUTH (5),

	/** southwest */
	SOUTHWEST (6),

	/** west */
	WEST (7),

	/** northwest */
	NORTHWEST (8);

	/* instance members */

	/** the integer directionID that is independant of coordinate system type (i.e. has meaning for square-cell, hex, diamond, or other coordinate-system-type maps) */
	private final int directionID;

	/**
	 * @param aDirectionID Numeric direction value
	 */
	private SquareMapDirection (final int aDirectionID)
	{
		directionID = aDirectionID;
	}

	/**
	 * @return Numeric direction value
	 */
	public final int getDirectionID ()
	{
		return directionID;
	}

	/** Directions for traversing from a set of coordinates through all the map cells adjacent to those coordinates, not including the cell we started from */
	public final static SquareMapDirection [] DIRECTIONS_TO_TRAVERSE_ADJACENT_CELLS = {NORTHWEST, EAST, EAST, SOUTH, SOUTH, WEST, WEST, NORTH};
}
