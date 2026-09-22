package momime.common.database;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import momime.common.MomException;

/**
 * Everytime we need the image for a particular bitmask, rather than having to apply all the reduction rules before we
 * can look up the image in the graphics XML, instead we start from every possible bitmask, apply the reduction rules
 * up front and store the result, then the values can be read off directly out of the HashMap.
 */
public final class SmoothingSystemEx extends SmoothingSystem
{
	/** Map of smoothed bitmasks, to the list of unsmoothed bitmasks that reduce to it */
	private final Map<String, List<String>> bitmasksMap = new HashMap<String, List<String>> ();
	
	/**
	 * @param directions Directions value from the parent TileSet
	 * @return All possible unsmoothed bitmasks for this smoothing system, e.g. for 8 directions and maxValue=1 generates a list 256 long
	 */
	final List<String> listUnsmoothedBitmasks (final int directions)
	{
		final List<String> bitmasks = new ArrayList<String> ();
		final int base = getMaxValueEachDirection () + 1; 
		
		final int count = (int) Math.pow (base, directions);
		for (int n = 0; n < count; n++)
		{
			String bitmask = Integer.toString (n, base);
			
			while (bitmask.length () < directions)
				bitmask = "0" + bitmask;
				
			bitmasks.add (bitmask);
		}
		
		return bitmasks;
	}
	
	/**
	 * Tests whether one smoothing reduction condition matches the supplied bitmask.
	 * Each rule can have 1..3 such conditions.  Its valid to pass in all 3 values as null in which case its an automatic pass,
	 * however if any values are non-null then they must all be non-null.
	 *  
	 * @param bitmask The bitmask to test
	 * @param directions The directions (indices into the bitmask) to test
	 * @param repetitions Expected number of matches
	 * @param value List of acceptable values
	 * @return True if the bitmask passes the test, false if it doesn't
	 * @throws MomException If one input value is null but another is non-null
	 */
	final boolean smoothingReductionConditionMatches (final String bitmask, final String directions, final Integer repetitions, final String value) throws MomException
	{
		final boolean matches;
		if ((directions == null) && (repetitions == null) && (value == null))
			matches = true;
		else
		{
			// At least one value filled in, so make sure they all are
			if (directions == null)
				throw new MomException ("smoothingReductionConditionMatches: Directions null but repetitions or value non-null");
			
			if (repetitions == null)
				throw new MomException ("smoothingReductionConditionMatches: Repetitions null but directions or value non-null");
			
			if (value == null)
				throw new MomException ("smoothingReductionConditionMatches: Value null but directions or repetitions non-null");
			
			// Do real check
			int count = 0;
			for (int n = 0; n < directions.length (); n++)
			{
				final int thisDirection = Integer.parseInt (directions.substring (n, n+1));
				final String bit = bitmask.substring (thisDirection-1, thisDirection);
				if (value.indexOf (bit) >= 0)
					count++;
			}
			matches = (count == repetitions);
		}
		
		return matches;
	}

	/**
	 * Replaces one value in a bitmask.  Its valid to pass in both values as null in which case nothing happens,
	 * however if either value is non-null then they must both be non-null.
	 *  
	 * @param bitmask The bitmask to start from
	 * @param direction The direction to set
	 * @param value Value to set
	 * @return Bitmask with the (direction)th character set to 'value'
	 * @throws MomException If one input value is null but the other is non-null
	 */
	final String applySmoothingReductionReplacement (final String bitmask, final Integer direction, final Integer value) throws MomException
	{
		final String out;
		if ((direction == null) && (value == null))
			out = bitmask;
		else
		{
			// At least one value filled in, so make sure they all are
			if (direction == null)
				throw new MomException ("applySmoothingReductionReplacement: Direction null but value non-null");
			
			if (value == null)
				throw new MomException ("applySmoothingReductionReplacement: Value null but direction non-null");
			
			// Do real replacement
			out = bitmask.substring (0, direction-1) + value + bitmask.substring (direction);  
		}
		
		return out;
	}

	/**
	 * @param bitmask The bitmask to start from
	 * @return The bitmask with all of the smoothing reduction rules defined under this smoothing system applied to it
	 * @throws MomException If there are invalid rules defined, i.e. with a mixture of null and non-null condition/set rules
	 */
	final String applySmoothingReductionRules (final String bitmask) throws MomException
	{
		String out = bitmask;
		for (final SmoothingReduction rule : getSmoothingReduction ())
			if ((smoothingReductionConditionMatches (out, rule.getDirection1 (), rule.getRepetitions1 (), rule.getValue1 ())) &&
				(smoothingReductionConditionMatches (out, rule.getDirection2 (), rule.getRepetitions2 (), rule.getValue2 ())) &&
				(smoothingReductionConditionMatches (out, rule.getDirection3 (), rule.getRepetitions3 (), rule.getValue3 ())))
			{
				out = applySmoothingReductionReplacement (out, rule.getSetDirection1 (), rule.getSetValue1 ());
				out = applySmoothingReductionReplacement (out, rule.getSetDirection2 (), rule.getSetValue2 ());
			}
		
		return out;
	}

	/**
	 * Builds up the complete bitmasksMap
	 * 
	 * @param directions Directions value from the parent TileSet
	 * @throws MomException If there are invalid rules defined, i.e. with a mixture of null and non-null condition/set rules
	 */
	final void buildMap (final int directions) throws MomException
	{
		final List<String> bitmasks = listUnsmoothedBitmasks (directions);
		for (final String unsmoothed : bitmasks)
		{
			final String smoothed = applySmoothingReductionRules (unsmoothed);
			
			// See if the smoothed bitmask exists in the map already
			List<String> unsmoothedList = bitmasksMap.get (smoothed);
			if (unsmoothedList == null)
			{
				unsmoothedList = new ArrayList<String> ();
				bitmasksMap.put (smoothed, unsmoothedList);
			}
			
			// Add new unsmoothed bitmask to the list
			unsmoothedList.add (unsmoothed);
		}
	}
	
	/**
	 * @return Map of smoothed bitmasks, to the list of unsmoothed bitmasks that reduce to it
	 */
	final Map<String, List<String>> getBitmasksMap ()
	{
		return bitmasksMap;
	}
}