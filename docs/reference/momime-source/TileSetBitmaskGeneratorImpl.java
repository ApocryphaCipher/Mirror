package momime.client.calculations;

import com.ndg.map.CoordinateSystemUtils;
import com.ndg.map.coordinates.MapCoordinates2DEx;
import com.ndg.map.coordinates.MapCoordinates3DEx;

import momime.client.MomClient;
import momime.client.config.MomImeClientConfig;
import momime.client.graphics.database.GraphicsDatabaseConstants;
import momime.common.database.CombatMapLayerID;
import momime.common.database.CommonDatabaseConstants;
import momime.common.database.OverlandMapSize;
import momime.common.database.RecordNotFoundException;
import momime.common.database.SmoothedTileTypeEx;
import momime.common.database.TileSetEx;
import momime.common.messages.CombatMapSize;
import momime.common.messages.MapAreaOfCombatTiles;
import momime.common.messages.MemoryGridCell;
import momime.common.utils.CombatMapUtils;

/**
 * Tile sets have their tiles indexed by a bitmask with a value corresponding to each adjacent tile,
 * so 00110000 might represent grass everywhere except mountains right and down-right.
 * 
 * This class is responsible for building those bitmasks.  Moved out of OverlandMapBitmapGenerator and
 * CombatMapBitmapGenerator to make it more unit testable.
 */
public final class TileSetBitmaskGeneratorImpl implements TileSetBitmaskGenerator
{
	/** Multiplayer client */
	private MomClient client;
	
	/** Coordinate system utils */
	private CoordinateSystemUtils coordinateSystemUtils;
	
	/** Client config, containing various combat map settings */
	private MomImeClientConfig clientConfig;
	
	/** Combat map utils */
	private CombatMapUtils combatMapUtils;

	/**
	 * @param smoothedTileType Smoothed tile type to generate bitmask for 
	 * @param riverDirections List of directions in which a river runs from this tile, e.g. a tile with a river heading off the tile downwards = 5
	 * @param x X coordinate of overland map tile we want to generate bitmask for
	 * @param y Y coordinate of overland map tile we want to generate bitmask for
	 * @param planeNo Plane of overland map tile we want to generate bitmask for
	 * @return Bitmask describing adjacent tiles to use to select correct tile image to draw
	 * @throws RecordNotFoundException If the tile set or smoothing system can't be found 
	 */
	@Override
	public final String generateOverlandMapBitmask (final SmoothedTileTypeEx smoothedTileType, final String riverDirections, final int x, final int y, final int planeNo)
		throws RecordNotFoundException
	{
		// If this is ticked then fix the bitmask
		// If a land based tile, want to assume grass in every direction (e.g. for mountains, draw a single mountain), so want 11111111
		
		// But for a sea tile, this looks really daft - you get a 'sea' of lakes surrounded by grass!  So we have to force these to 00000000 instead
		// to make it look remotely sensible
		
		// Rather than hard coding which tile types need 00000000 and which need 11111111, the graphics XML file has a special
		// entry under every tile for the image to use for 'NoSmooth' = No Smoothing
		final StringBuffer bitmask = new StringBuffer ();
		if (!getClientConfig ().isOverlandSmoothTerrain ())
			bitmask.append (CommonDatabaseConstants.TILE_BITMASK_NO_SMOOTHING);
		else							
		{
			final TileSetEx overlandMapTileSet = getClient ().getClientDB ().findTileSet (CommonDatabaseConstants.TILE_SET_OVERLAND_MAP, "generateOverlandMapBitmask");			
			final OverlandMapSize overlandMapSize = getClient ().getSessionDescription ().getOverlandMapSize ();
			final int maxDirection = getCoordinateSystemUtils ().getMaxDirection (overlandMapSize.getCoordinateSystemType ());
			
			// 3 possibilities for how we create the bitmask
			// 0 = force 00000000
			// 1 = use 0 for this type of tile, 1 for anything else (assume grass)
			// 2 = use 0 for this type of tile, 1 for anything else (assume grass), 2 for rivers (in a joining direction)
			final int maxValueInEachDirection = overlandMapTileSet.findSmoothingSystem
				(smoothedTileType.getSmoothingSystemID (), "generateOverlandMapBitmask").getMaxValueEachDirection ();
			
			if (maxValueInEachDirection == 0)
			{
				for (int d = 1; d <= maxDirection; d++)
					bitmask.append ("0");
			}
			
			// If a river tile, decide whether to treat this direction as a river based on the RiverDirections FROM this tile, not by looking at adjoining tiles
			// NB. This is only inland rivers - oceanside river mouths are just special shore/ocean tiles
			else if ((maxValueInEachDirection == 1) && (riverDirections != null))
			{
				for (int d = 1; d <= maxDirection; d++)
					if (riverDirections.contains (Integer.valueOf (d).toString ()))
						bitmask.append ("0");
					else
						bitmask.append ("1");
			}
			
			// Normal type of smoothing
			else
			{
				for (int d = 1; d <= maxDirection; d++)
					
					// Want rivers? i.e. is this an ocean tile
					if ((maxValueInEachDirection == 2) && (riverDirections != null) &&
						(riverDirections.contains (Integer.valueOf (d).toString ())))
						
						bitmask.append ("2");
					else
					{
						final MapCoordinates3DEx coords = new MapCoordinates3DEx (x, y, planeNo);
						if (getCoordinateSystemUtils ().move3DCoordinates (overlandMapSize, coords, d))
						{
							final MemoryGridCell otherGc = getClient ().getOurPersistentPlayerPrivateKnowledge ().getFogOfWarMemory ().getMap ().getPlane ().get
								(coords.getZ ()).getRow ().get (coords.getY ()).getCell ().get (coords.getX ());
							final String otherTileTypeID = (otherGc.getTerrainData () == null) ? null : otherGc.getTerrainData ().getTileTypeID ();
							
							if ((otherTileTypeID == null) || (otherTileTypeID.equals (smoothedTileType.getTileTypeID ())) ||
								(otherTileTypeID.equals (smoothedTileType.getSecondaryTileTypeID ())) ||
								(otherTileTypeID.equals (smoothedTileType.getTertiaryTileTypeID ())))
								
								bitmask.append ("0");
							else
								bitmask.append ("1");
						}
						else
							bitmask.append ("0");
					}
			}
		}
		
		return bitmask.toString ();
	}
	
	/**
	 * @param combatTerrain Details of combat map terrain
	 * @param smoothedTileType Smoothed tile type to generate bitmask for 
	 * @param x X coordinate of combat map tile we want to generate bitmask for
	 * @param y Y coordinate of combat map tile we want to generate bitmask for
	 * @param layer Combat map layer of map tile we want to generate bitmask for
	 * @return Bitmask describing adjacent tiles to use to select correct tile image to draw
	 * @throws RecordNotFoundException If the tile set or smoothing system can't be found 
	 */
	@Override
	public final String generateCombatMapBitmask (final MapAreaOfCombatTiles combatTerrain,
		final SmoothedTileTypeEx smoothedTileType, final CombatMapLayerID layer, final int x, final int y)
		throws RecordNotFoundException
	{
		// If this is ticked then fix the bitmask
		// If a land based tile, want to assume grass in every direction (e.g. for mountains, draw a single mountain), so want 11111111
		
		// But for a sea tile, this looks really daft - you get a 'sea' of lakes surrounded by grass!  So we have to force these to 00000000 instead
		// to make it look remotely sensible
		
		// Rather than hard coding which tile types need 00000000 and which need 11111111, the graphics XML file has a special
		// entry under every tile for the image to use for 'NoSmooth' = No Smoothing
		final StringBuffer bitmask = new StringBuffer ();
		if (!getClientConfig ().isCombatSmoothTerrain ())
			bitmask.append (CommonDatabaseConstants.TILE_BITMASK_NO_SMOOTHING);
		else							
		{
			final TileSetEx combatMapTileSet = getClient ().getClientDB ().findTileSet (GraphicsDatabaseConstants.TILE_SET_COMBAT_MAP, "generateCombatMapBitmask");
			final CombatMapSize mapSize = getClient ().getSessionDescription ().getCombatMapSize ();
			final int maxDirection = getCoordinateSystemUtils ().getMaxDirection (mapSize.getCoordinateSystemType ());
			
			// No rivers to worry about like overland tiles, so only 2 possibilities for how we create the bitmask
			// 0 = force 00000000
			// 1 = use 0 for this type of tile, 1 for anything else (assume grass)
			final int maxValueInEachDirection = combatMapTileSet.findSmoothingSystem
				(smoothedTileType.getSmoothingSystemID (), "generateCombatMapBitmask").getMaxValueEachDirection ();
			
			if (maxValueInEachDirection == 0)
			{
				for (int d = 1; d <= maxDirection; d++)
					bitmask.append ("0");
			}
			
			// Normal type of smoothing
			else
			{
				for (int d = 1; d <= maxDirection; d++)
				{
					final MapCoordinates2DEx coords = new MapCoordinates2DEx (x, y);
					if (getCoordinateSystemUtils ().move2DCoordinates (mapSize, coords, d))
					{
						final String otherCombatTileTypeID = getCombatMapUtils ().getCombatTileTypeForLayer
							(combatTerrain.getRow ().get (coords.getY ()).getCell ().get (coords.getX ()), layer);
						
						if ((otherCombatTileTypeID == null) || (otherCombatTileTypeID.equals (smoothedTileType.getCombatTileTypeID ())))
							bitmask.append ("0");
						else
							bitmask.append ("1");
					}
					else
						bitmask.append ("0");
				}
			}
		}
		
		return bitmask.toString ();
	}

	/**
	 * @return Multiplayer client
	 */
	public final MomClient getClient ()
	{
		return client;
	}
	
	/**
	 * @param obj Multiplayer client
	 */
	public final void setClient (final MomClient obj)
	{
		client = obj;
	}

	/**
	 * @return Coordinate system utils
	 */
	public final CoordinateSystemUtils getCoordinateSystemUtils ()
	{
		return coordinateSystemUtils;
	}

	/**
	 * @param csu Coordinate system utils
	 */
	public final void setCoordinateSystemUtils (final CoordinateSystemUtils csu)
	{
		coordinateSystemUtils = csu;
	}
	
	/**
	 * @return Client config, containing various combat map settings
	 */	
	public final MomImeClientConfig getClientConfig ()
	{
		return clientConfig;
	}

	/**
	 * @param config Client config, containing various combat map settings
	 */
	public final void setClientConfig (final MomImeClientConfig config)
	{
		clientConfig = config;
	}

	/**
	 * @return Combat map utils
	 */
	public final CombatMapUtils getCombatMapUtils ()
	{
		return combatMapUtils;
	}

	/**
	 * @param util Combat map utils
	 */
	public final void setCombatMapUtils (final CombatMapUtils util)
	{
		combatMapUtils = util;
	}
}