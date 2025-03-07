import { useState, useRef, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { 
  Paper, 
  IconButton, 
  InputBase, 
  Popover, 
  Box, 
  Typography, 
  FormControl, 
  Select, 
  MenuItem, 
  Stack,
  Chip,
  Button,
  Divider,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  ClickAwayListener,
  Popper
} from '@mui/material'
import { 
  Search, 
  TuneRounded, 
  AccessTime, 
  HighQuality, 
  Language, 
  Sort, 
  Clear,
  History,
  Close
} from '@mui/icons-material'
import { useSearch } from '../contexts/SearchContext'

const SearchBar = () => {
  const [searchTerm, setSearchTerm] = useState('');
  const [anchorEl, setAnchorEl] = useState(null);
  const [filters, setFilters] = useState({
    duration: 'any',
    uploadDate: 'any',
    quality: 'any',
    language: 'any',
    sortBy: 'relevance'
  });
  const [activeFilters, setActiveFilters] = useState([]);
  
  // Search suggestions state
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [suggestionsAnchorEl, setSuggestionsAnchorEl] = useState(null);
  
  const searchInputRef = useRef(null);
  const navigate = useNavigate();
  
  // Get search context
  const { 
    suggestions, 
    getSuggestions, 
    addToSearchHistory, 
    getRecentSearches,
    removeFromSearchHistory,
    clearSearchHistory
  } = useSearch();
  
  // Recent searches
  const [recentSearches, setRecentSearches] = useState([]);
  
  // Update recent searches when component mounts
  useEffect(() => {
    setRecentSearches(getRecentSearches());
  }, [getRecentSearches]);
  
  // Handle input change and generate suggestions
  const handleInputChange = (e) => {
    const value = e.target.value;
    setSearchTerm(value);
    
    if (value.trim()) {
      getSuggestions(value);
      setSuggestionsAnchorEl(searchInputRef.current);
      setShowSuggestions(true);
    } else {
      setShowSuggestions(false);
    }
  };
  
  // Handle suggestion click
  const handleSuggestionClick = (suggestion) => {
    setSearchTerm(suggestion);
    setShowSuggestions(false);
    handleSearch(suggestion);
  };
  
  // Handle search submission
  const handleSubmit = (e) => {
    e.preventDefault();
    handleSearch(searchTerm);
  };
  
  // Common search handling
  const handleSearch = (term) => {
    if (term && term.trim()) {
      // Add to search history
      addToSearchHistory(term);
      
      // Update recent searches
      setRecentSearches(getRecentSearches());
      
      // Build query string with filters
      let queryParams = new URLSearchParams();
      
      // Add active filters to query params
      activeFilters.forEach(filter => {
        queryParams.append(filter.key, filter.value);
      });
      
      // Navigate to search page with term and filters
      const queryString = queryParams.toString();
      navigate(`/search/${term}${queryString ? `?${queryString}` : ''}`);
    }
  };
  
  // Handle filter menu open
  const handleFilterClick = (event) => {
    setAnchorEl(event.currentTarget);
  };

  // Handle filter menu close
  const handleFilterClose = () => {
    setAnchorEl(null);
  };

  // Handle filter change
  const handleFilterChange = (key, value) => {
    setFilters(prev => ({
      ...prev,
      [key]: value
    }));
  };

  // Apply filters
  const applyFilters = () => {
    const newActiveFilters = [];
    
    // Add filters that are not set to 'any'
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== 'any') {
        newActiveFilters.push({
          key,
          value,
          label: `${getFilterLabel(key)}: ${getValueLabel(key, value)}`
        });
      }
    });
    
    setActiveFilters(newActiveFilters);
    handleFilterClose();
    
    // Focus back on search input
    if (searchInputRef.current) {
      searchInputRef.current.focus();
    }
  };

  // Reset filters
  const resetFilters = () => {
    setFilters({
      duration: 'any',
      uploadDate: 'any',
      quality: 'any',
      language: 'any',
      sortBy: 'relevance'
    });
  };

  // Remove a single filter
  const removeFilter = (filterKey) => {
    setActiveFilters(prev => prev.filter(filter => filter.key !== filterKey));
    setFilters(prev => ({
      ...prev,
      [filterKey]: 'any'
    }));
  };

  // Clear all filters
  const clearAllFilters = () => {
    setActiveFilters([]);
    resetFilters();
  };
  
  // Remove a search from history
  const handleRemoveSearch = (e, term) => {
    e.stopPropagation();
    removeFromSearchHistory(term);
    setRecentSearches(getRecentSearches());
  };
  
  // Clear all search history
  const handleClearSearchHistory = () => {
    clearSearchHistory();
    setRecentSearches([]);
  };

  // Get human-readable filter label
  const getFilterLabel = (key) => {
    const labels = {
      duration: 'Duration',
      uploadDate: 'Upload Date',
      quality: 'Quality',
      language: 'Language',
      sortBy: 'Sort By'
    };
    return labels[key] || key;
  };

  // Get human-readable value label
  const getValueLabel = (key, value) => {
    const valueLabels = {
      duration: {
        'any': 'Any',
        'short': 'Under 4 minutes',
        'medium': '4-20 minutes',
        'long': 'Over 20 minutes'
      },
      uploadDate: {
        'any': 'Any time',
        'hour': 'Last hour',
        'day': 'Today',
        'week': 'This week',
        'month': 'This month',
        'year': 'This year'
      },
      quality: {
        'any': 'Any',
        'hd': 'HD',
        '4k': '4K'
      },
      language: {
        'any': 'Any',
        'en': 'English',
        'es': 'Spanish',
        'fr': 'French',
        'de': 'German',
        'ja': 'Japanese',
        'ko': 'Korean',
        'zh': 'Chinese'
      },
      sortBy: {
        'relevance': 'Relevance',
        'date': 'Upload date',
        'viewCount': 'View count',
        'rating': 'Rating'
      }
    };
    
    return valueLabels[key]?.[value] || value;
  };

  const open = Boolean(anchorEl);
  const id = open ? 'filter-popover' : undefined;
  
  // Common styles for select components
  const selectStyles = {
    color: 'var(--text-primary)',
    '.MuiOutlinedInput-notchedOutline': {
      borderColor: 'var(--border-color)'
    },
    '&:hover .MuiOutlinedInput-notchedOutline': {
      borderColor: 'var(--text-secondary)'
    },
    '&.Mui-focused .MuiOutlinedInput-notchedOutline': {
      borderColor: 'var(--primary-color)'
    },
    '.MuiSvgIcon-root': {
      color: 'var(--text-secondary)'
    }
  };

  // Common styles for menu props
  const menuProps = {
    PaperProps: {
      sx: {
        backgroundColor: 'var(--card-bg)',
        border: '1px solid var(--border-color)',
        boxShadow: 'var(--card-hover-shadow)',
      }
    },
    MenuListProps: {
      sx: {
        '& .MuiMenuItem-root': {
          color: 'var(--text-primary)'
        }
      }
    }
  };

  // Common styles for menu items
  const menuItemStyles = {
    color: 'var(--text-primary)',
    '&:hover': {
      backgroundColor: 'rgba(255, 0, 0, 0.1)'
    },
    '&.Mui-selected': {
      backgroundColor: 'rgba(255, 0, 0, 0.2)',
      '&:hover': {
        backgroundColor: 'rgba(255, 0, 0, 0.3)'
      }
    }
  };

  return (
    <ClickAwayListener onClickAway={() => setShowSuggestions(false)}>
      <Box sx={{ width: '100%', position: 'relative' }}>
        <Paper
          component="form"
          onSubmit={handleSubmit}
          elevation={0}
          sx={{
            display: 'flex',
            alignItems: 'center',
            borderRadius: '24px',
            border: '1px solid var(--border-color)',
            pl: 2,
            pr: 0.5,
            py: 0.5,
            width: { xs: '100%', sm: '350px' },
            maxWidth: '600px',
            backgroundColor: 'var(--secondary-bg)',
            transition: 'all 0.2s ease',
            '&:hover': {
              border: '1px solid var(--text-secondary)',
              boxShadow: '0 1px 6px rgba(255, 77, 77, 0.15)',
            },
            '&:focus-within': {
              border: '1px solid var(--primary-color)',
              boxShadow: '0 1px 6px rgba(255, 77, 77, 0.25)',
            }
          }}
        >
          <InputBase
            inputRef={searchInputRef}
            sx={{ 
              ml: 1, 
              flex: 1,
              color: 'var(--text-primary)',
              '& .MuiInputBase-input::placeholder': {
                color: 'var(--text-secondary)',
                opacity: 0.7
              }
            }}
            placeholder="Search..."
            value={searchTerm}
            onChange={handleInputChange}
            onFocus={() => {
              if (searchTerm.trim() || recentSearches.length > 0) {
                setSuggestionsAnchorEl(searchInputRef.current);
                setShowSuggestions(true);
              }
            }}
            inputProps={{ 'aria-label': 'search youtube' }}
          />
          
          <IconButton 
            aria-describedby={id}
            onClick={handleFilterClick}
            sx={{ 
              color: activeFilters.length > 0 ? 'var(--primary-color)' : 'var(--text-secondary)',
              '&:hover': { color: 'var(--primary-color)' }
            }}
          >
            <TuneRounded />
          </IconButton>
          
          <IconButton 
            type="submit" 
            sx={{ 
              p: '10px', 
              color: 'var(--text-secondary)',
              '&:hover': { color: 'var(--primary-color)' }
            }}
          >
            <Search />
          </IconButton>
        </Paper>
        
        {/* Search suggestions */}
        <Popper
          open={showSuggestions}
          anchorEl={suggestionsAnchorEl}
          placement="bottom-start"
          style={{ zIndex: 1300, width: searchInputRef.current?.offsetWidth }}
        >
          <Paper
            sx={{
              width: '100%',
              mt: 1,
              backgroundColor: 'var(--card-bg)',
              border: '1px solid var(--border-color)',
              boxShadow: 'var(--card-hover-shadow)',
              borderRadius: '8px',
              overflow: 'hidden'
            }}
          >
            <List sx={{ p: 0 }}>
              {/* Recent searches header */}
              {recentSearches.length > 0 && !searchTerm.trim() && (
                <ListItem
                  sx={{
                    backgroundColor: 'rgba(0, 0, 0, 0.2)',
                    display: 'flex',
                    justifyContent: 'space-between'
                  }}
                >
                  <Typography variant="body2" color="var(--text-secondary)">
                    Recent Searches
                  </Typography>
                  <Button
                    size="small"
                    onClick={handleClearSearchHistory}
                    sx={{ 
                      color: 'var(--text-secondary)',
                      '&:hover': { color: 'var(--primary-color)' }
                    }}
                  >
                    Clear All
                  </Button>
                </ListItem>
              )}
              
              {/* Recent searches */}
              {recentSearches.length > 0 && !searchTerm.trim() && recentSearches.map((term) => (
                <ListItem
                  key={term}
                  button
                  onClick={() => handleSuggestionClick(term)}
                  sx={{
                    '&:hover': { backgroundColor: 'rgba(255, 0, 0, 0.08)' }
                  }}
                >
                  <ListItemIcon sx={{ minWidth: 36 }}>
                    <History sx={{ color: 'var(--text-secondary)' }} />
                  </ListItemIcon>
                  <ListItemText 
                    primary={term} 
                    sx={{ color: 'var(--text-primary)' }}
                  />
                  <IconButton
                    size="small"
                    onClick={(e) => handleRemoveSearch(e, term)}
                    sx={{ color: 'var(--text-secondary)' }}
                  >
                    <Close fontSize="small" />
                  </IconButton>
                </ListItem>
              ))}
              
              {/* Suggestions based on input */}
              {searchTerm.trim() && suggestions.map((suggestion) => (
                <ListItem
                  key={suggestion}
                  button
                  onClick={() => handleSuggestionClick(suggestion)}
                  sx={{
                    '&:hover': { backgroundColor: 'rgba(255, 0, 0, 0.08)' }
                  }}
                >
                  <ListItemIcon sx={{ minWidth: 36 }}>
                    <Search sx={{ color: 'var(--text-secondary)' }} />
                  </ListItemIcon>
                  <ListItemText 
                    primary={suggestion} 
                    sx={{ color: 'var(--text-primary)' }}
                  />
                </ListItem>
              ))}
              
              {/* No suggestions message */}
              {searchTerm.trim() && suggestions.length === 0 && (
                <ListItem>
                  <ListItemText 
                    primary="No suggestions found" 
                    sx={{ color: 'var(--text-secondary)', textAlign: 'center' }}
                  />
                </ListItem>
              )}
            </List>
          </Paper>
        </Popper>
        
        {/* Display active filters */}
        {activeFilters.length > 0 && (
          <Box sx={{ mt: 1, display: 'flex', flexWrap: 'wrap', gap: 1 }}>
            {activeFilters.map((filter) => (
              <Chip
                key={filter.key}
                label={filter.label}
                onDelete={() => removeFilter(filter.key)}
                size="small"
                sx={{
                  backgroundColor: 'rgba(255, 0, 0, 0.1)',
                  color: 'var(--text-primary)',
                  borderRadius: '4px',
                  '& .MuiChip-deleteIcon': {
                    color: 'var(--text-secondary)',
                    '&:hover': {
                      color: 'var(--primary-color)'
                    }
                  }
                }}
              />
            ))}
            
            <Chip
              label="Clear All"
              onClick={clearAllFilters}
              size="small"
              deleteIcon={<Clear />}
              onDelete={clearAllFilters}
              sx={{
                backgroundColor: 'rgba(255, 0, 0, 0.2)',
                color: 'var(--text-primary)',
                borderRadius: '4px',
                '& .MuiChip-deleteIcon': {
                  color: 'var(--primary-color)',
                }
              }}
            />
          </Box>
        )}
        
        {/* Filter popover */}
        <Popover
          id={id}
          open={open}
          anchorEl={anchorEl}
          onClose={handleFilterClose}
          anchorOrigin={{
            vertical: 'bottom',
            horizontal: 'left',
          }}
          transformOrigin={{
            vertical: 'top',
            horizontal: 'left',
          }}
          PaperProps={{
            sx: {
              mt: 1,
              p: 2,
              width: { xs: '280px', sm: '320px' },
              backgroundColor: 'var(--card-bg)',
              border: '1px solid var(--border-color)',
              boxShadow: 'var(--card-hover-shadow)',
            }
          }}
        >
          <Typography variant="h6" color="var(--text-primary)" gutterBottom>
            Advanced Filters
          </Typography>
          
          <Divider sx={{ borderColor: 'var(--border-color)', my: 1 }} />
          
          <Stack spacing={2} sx={{ mt: 2 }}>
            {/* Duration filter */}
            <FormControl fullWidth size="small">
              <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
                <AccessTime sx={{ color: 'var(--text-secondary)', fontSize: 20 }} />
                <Typography variant="body2" color="var(--text-primary)">
                  Duration
                </Typography>
              </Stack>
              <Select
                value={filters.duration}
                onChange={(e) => handleFilterChange('duration', e.target.value)}
                sx={selectStyles}
                MenuProps={menuProps}
              >
                <MenuItem value="any" sx={menuItemStyles}>Any</MenuItem>
                <MenuItem value="short" sx={menuItemStyles}>Under 4 minutes</MenuItem>
                <MenuItem value="medium" sx={menuItemStyles}>4-20 minutes</MenuItem>
                <MenuItem value="long" sx={menuItemStyles}>Over 20 minutes</MenuItem>
              </Select>
            </FormControl>
            
            {/* Upload date filter */}
            <FormControl fullWidth size="small">
              <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
                <AccessTime sx={{ color: 'var(--text-secondary)', fontSize: 20 }} />
                <Typography variant="body2" color="var(--text-primary)">
                  Upload Date
                </Typography>
              </Stack>
              <Select
                value={filters.uploadDate}
                onChange={(e) => handleFilterChange('uploadDate', e.target.value)}
                sx={selectStyles}
                MenuProps={menuProps}
              >
                <MenuItem value="any" sx={menuItemStyles}>Any time</MenuItem>
                <MenuItem value="hour" sx={menuItemStyles}>Last hour</MenuItem>
                <MenuItem value="day" sx={menuItemStyles}>Today</MenuItem>
                <MenuItem value="week" sx={menuItemStyles}>This week</MenuItem>
                <MenuItem value="month" sx={menuItemStyles}>This month</MenuItem>
                <MenuItem value="year" sx={menuItemStyles}>This year</MenuItem>
              </Select>
            </FormControl>
            
            {/* Quality filter */}
            <FormControl fullWidth size="small">
              <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
                <HighQuality sx={{ color: 'var(--text-secondary)', fontSize: 20 }} />
                <Typography variant="body2" color="var(--text-primary)">
                  Quality
                </Typography>
              </Stack>
              <Select
                value={filters.quality}
                onChange={(e) => handleFilterChange('quality', e.target.value)}
                sx={selectStyles}
                MenuProps={menuProps}
              >
                <MenuItem value="any" sx={menuItemStyles}>Any</MenuItem>
                <MenuItem value="hd" sx={menuItemStyles}>HD</MenuItem>
                <MenuItem value="4k" sx={menuItemStyles}>4K</MenuItem>
              </Select>
            </FormControl>
            
            {/* Language filter */}
            <FormControl fullWidth size="small">
              <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
                <Language sx={{ color: 'var(--text-secondary)', fontSize: 20 }} />
                <Typography variant="body2" color="var(--text-primary)">
                  Language
                </Typography>
              </Stack>
              <Select
                value={filters.language}
                onChange={(e) => handleFilterChange('language', e.target.value)}
                sx={selectStyles}
                MenuProps={menuProps}
              >
                <MenuItem value="any" sx={menuItemStyles}>Any</MenuItem>
                <MenuItem value="en" sx={menuItemStyles}>English</MenuItem>
                <MenuItem value="es" sx={menuItemStyles}>Spanish</MenuItem>
                <MenuItem value="fr" sx={menuItemStyles}>French</MenuItem>
                <MenuItem value="de" sx={menuItemStyles}>German</MenuItem>
                <MenuItem value="ja" sx={menuItemStyles}>Japanese</MenuItem>
                <MenuItem value="ko" sx={menuItemStyles}>Korean</MenuItem>
                <MenuItem value="zh" sx={menuItemStyles}>Chinese</MenuItem>
              </Select>
            </FormControl>
            
            {/* Sort by filter */}
            <FormControl fullWidth size="small">
              <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
                <Sort sx={{ color: 'var(--text-secondary)', fontSize: 20 }} />
                <Typography variant="body2" color="var(--text-primary)">
                  Sort By
                </Typography>
              </Stack>
              <Select
                value={filters.sortBy}
                onChange={(e) => handleFilterChange('sortBy', e.target.value)}
                sx={selectStyles}
                MenuProps={menuProps}
              >
                <MenuItem value="relevance" sx={menuItemStyles}>Relevance</MenuItem>
                <MenuItem value="date" sx={menuItemStyles}>Upload date</MenuItem>
                <MenuItem value="viewCount" sx={menuItemStyles}>View count</MenuItem>
                <MenuItem value="rating" sx={menuItemStyles}>Rating</MenuItem>
              </Select>
            </FormControl>
          </Stack>
          
          <Stack direction="row" spacing={1} sx={{ mt: 3, justifyContent: 'flex-end' }}>
            <Button 
              onClick={resetFilters}
              sx={{ 
                color: 'var(--text-secondary)',
                '&:hover': {
                  backgroundColor: 'rgba(255, 255, 255, 0.05)'
                }
              }}
            >
              Reset
            </Button>
            <Button 
              variant="contained" 
              onClick={applyFilters}
              sx={{ 
                backgroundColor: 'var(--primary-color)',
                '&:hover': {
                  backgroundColor: 'var(--primary-color-dark)'
                }
              }}
            >
              Apply
            </Button>
          </Stack>
        </Popover>
      </Box>
    </ClickAwayListener>
  )
}

export default SearchBar